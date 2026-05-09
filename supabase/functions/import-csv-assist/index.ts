// Supabase Edge Function — 카드사 CSV import 보조.
// 두 가지 모드:
//  - "mapping": CSV 헤더 + 샘플 row를 보고 우리 양식의 어느 필드(date/amount/merchant 등)에
//    어느 컬럼이 매핑되는지 추정.
//  - "classify": 가맹점명 리스트를 보고 사용자 기존 카테고리/태그에 매핑하거나 신규 제안.
//
// 클라이언트는 사용자 JWT만 들고 호출. ANTHROPIC_API_KEY는 환경변수에만.
// 배포: mcp__supabase__deploy_edge_function 으로 이 파일 통째로 업로드.

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import Anthropic from "npm:@anthropic-ai/sdk@0.73.0";
import * as XLSX from "npm:xlsx@0.18.5";

const MAPPING_SYSTEM = `당신은 한국 신용/체크카드 명세서(이용내역) CSV·XLS 가져오기 보조입니다. 파일 상단 row들을 보고 (1) 진짜 헤더 row가 어디인지, (2) 어느 컬럼이 무엇인지 추정합니다.

지원 범위: 신용/체크카드 명세서 전용 (모든 거래가 같은 방향=지출인 양식).
미지원 (반드시 차단): 은행 통장 거래내역 — 입금·출금이 한 시트에 섞여 있어서 자동 분류 시 본인 계좌 간 이체나 카드 결제대금이 이중 카운트됨. 통장 양식이 의심되면 unsupportedKind를 "bank"로 응답 (다른 필드는 dummy 0/null로 채워도 됨).

통장 양식 판별 신호 (하나라도 해당하면 unsupportedKind: "bank"):
- "입금"·"출금"·"입금액"·"출금액"·"맡기신금액"·"찾으신금액" 같은 컬럼이 둘 다 또는 한 쪽이라도 헤더에 있음
- "거래후잔액"·"잔액" 컬럼 (통장 거래내역의 특징, 카드 명세서엔 없음)
- "이체"·"송금"·"자동이체" 키워드가 가맹점/적요 컬럼에 다수 등장
- 양식 제목·시트명에 "거래내역"·"입출금"·"통장"·"예금" 단어 포함

출력은 반드시 단일 JSON 객체만. 설명·마크다운·코드블록 X. 첫 글자가 { 로 시작하고 } 로 끝납니다.

JSON 스키마:
{
  "headerRowIndex": number,        // 진짜 헤더 row의 0-based index (파일 첫 줄=0). 카드사가 상단에 제목 row를 두면 1 또는 2.
  "dateCol": number,               // 거래일/이용일/승인일 컬럼 인덱스 (헤더 row 기준, 필수)
  "amountCol": number,             // 금액 컬럼 인덱스 (필수)
  "merchantCol": number,           // 가맹점/이용처 컬럼 인덱스 (필수)
  "cardCol": number | null,        // 카드명/결제수단 컬럼 (선택)
  "memoCol": number | null,        // 메모/비고 컬럼 (선택)
  "statusCol": number | null,      // 거래 상태/승인구분 컬럼 (선택). "승인구분"/"거래구분"/"승인여부"/"상태"
  "excludedStatuses": string[],    // statusCol 값이 이 중 하나면 그 row 제외. 예: ["취소", "반려", "거절", "거부"]
  "dateFormat": string,            // 추정 형식. 예: "YYYY-MM-DD" "YYYY/MM/DD" "YYYY.MM.DD" "YYYYMMDD" "YYYY년 MM월 DD일"
  "amountSign": string,            // "positive" | "negative" | "absolute" — 지출이 어떤 부호인지
  "confidence": string,            // "high" | "medium" | "low"
  "note": string,                  // 사용자에게 보여줄 한 줄 설명 (한국어)
  "unsupportedKind": string | null // 카드 명세서가 아니라고 판단되면 "bank". 정상 카드 명세서는 null.
}

규칙:
- 한국 카드사 파일은 상단에 "실시간 이용내역" 같은 제목 row가 1~2줄 있고, 그 다음 줄이 진짜 헤더(이용일자/가맹점명 등)인 경우가 흔함. 헤더는 컬럼명만 있는 row (숫자/날짜 데이터 X).
- **row[0]에 채워진 셀이 1~2개뿐이고 나머지가 비어있으면 그건 큰 제목**. 그 경우 headerRowIndex >= 1.
- 진짜 헤더가 row 0이면 headerRowIndex: 0.
- 흔한 헤더 컬럼명: "이용일자/거래일자/승인일자", "이용가맹점/가맹점명/이용처", "이용금액/승인금액/청구금액"
- 청구금액과 이용금액이 둘 다 있으면 "이용금액"(실제 발생액) 우선
- **마스킹된 카드번호 컬럼(예: "5***-****-****-810*", "카드종류"라는 이름이지만 마스킹 번호인 경우)은 cardCol로 매핑하지 마세요**. cardCol은 "신한카드"/"카카오페이" 같은 결제수단 이름일 때만. 마스킹 번호면 cardCol: null.
- 부호 추정: 데이터 row에 -가 일관적이면 negative, 그 외 positive 또는 absolute
- 컬럼 인덱스는 0부터 시작 (헤더 row의 컬럼 순서)
- 매핑이 모호하면 confidence를 medium/low로 표시하고 note에 이유 한 줄

거래 상태 컬럼 (중요):
- 카드사 파일에는 "승인구분"/"거래구분"/"상태" 같은 컬럼이 있어 같은 거래의 정상/취소가 표시됨
- "승인구분" 컬럼 값이 "전표접수"=정상, "취소"=취소된 거래인 경우가 흔함
- 카드사 명세서 합계는 **취소된 거래를 빼고** 계산되므로 우리도 일치시켜야 함
- 그런 컬럼이 있으면 statusCol에 인덱스, excludedStatuses에 ["취소"] 같은 값을 넣어 자동 제외
- 없으면 statusCol: null, excludedStatuses: []

예시 1 (제목 row + 승인구분 컬럼):
  row[0]: ["실시간 이용내역", "", "", "", "", ""]  ← 큰 제목
  row[1]: ["승인일", "가맹점명", "승인금액", "이용구분", "카드종류", "승인구분"]  ← 진짜 헤더
  row[2]: ["2026-04-25", "스타벅스", "5,800", "일시불", "신한카드", "전표접수"]  ← 정상
  row[3]: ["2026-04-25", "택시_가승인", "10,400", "일시불", "신한카드", "취소"]  ← 취소
  → { "headerRowIndex": 1, "dateCol": 0, "merchantCol": 1, "amountCol": 2, "cardCol": 4, "memoCol": null, "statusCol": 5, "excludedStatuses": ["취소"], "unsupportedKind": null, ... }

예시 2 (헤더가 첫 줄, 상태 컬럼 없음):
  row[0]: ["거래일자", "가맹점", "이용금액"]
  row[1]: ["2026-04-25", "스타벅스", "5,800"]
  → { "headerRowIndex": 0, "dateCol": 0, "merchantCol": 1, "amountCol": 2, "statusCol": null, "excludedStatuses": [], "unsupportedKind": null, ... }

예시 3 (통장 거래내역 차단):
  row[0]: ["거래일자", "적요", "출금액", "입금액", "거래후잔액", "거래점"]
  row[1]: ["2026-04-25", "스타벅스", "5,800", "", "1,234,200", "온라인"]
  row[2]: ["2026-04-25", "월급", "", "3,500,000", "4,734,200", "회사"]
  → { "unsupportedKind": "bank", "confidence": "low", "note": "통장 거래내역으로 보여요. AI 정리는 카드사 명세서 전용이에요.", "headerRowIndex": 0, "dateCol": 0, "amountCol": 0, "merchantCol": 0, "cardCol": null, "memoCol": null, "statusCol": null, "excludedStatuses": [], "dateFormat": "auto", "amountSign": "absolute" }

note는 결정 근거 한 줄, 친근한 톤. 예: "승인일·가맹점명·승인금액으로 매핑했고, 취소된 거래는 자동으로 빼드릴게요"`;

const CLASSIFY_SYSTEM = `당신은 한국 가계부 카테고리 분류 보조입니다. 가맹점명 리스트를 보고 사용자의 기존 카테고리/태그에 매핑하거나 새로 제안합니다.

출력은 반드시 단일 JSON 객체만. 설명·마크다운·코드블록 X. 첫 글자가 { 로 시작하고 } 로 끝납니다.

JSON 스키마:
{
  "items": [
    {
      "merchant": string,         // 입력된 가맹점명 그대로
      "major": string,            // 카테고리 (사용자 기존 우선, 없으면 신규 제안)
      "sub": string | null,       // 태그 (선택, 사용자 기존 우선)
      "isNewMajor": boolean,      // 카테고리가 사용자 기존 목록에 없는 신규인지
      "isNewSub": boolean,        // 태그가 사용자 기존 목록에 없는 신규인지
      "confidence": string        // "high" | "medium" | "low"
    }
  ]
}

규칙:
- 사용자 기존 카테고리/태그가 충분하면(3개 이상) 그걸 최대한 활용.
- **사용자 카테고리가 '기타'만 있거나 2개 이하로 빈약하면 적극적으로 신규 카테고리를 제안**. 일반적인 한국 가계부 카테고리: 식비, 카페, 교통, 쇼핑, 통신, 구독, 의료, 미용, 주거, 문화, 게임, 자동차 등.
- **'기타'로 분류하는 건 정말 모르는 가맹점만**. 일반 브랜드/업종(스타벅스/GS25/카카오택시/넷슨/넷플릭스/배달의민족 등)은 절대 '기타'로 보내지 말고 적절한 카테고리에.
- 가맹점명에 지점/지역이 붙으면 본사명 기준으로 분류 (예: "스타벅스 강남역점" → 카페)
- 가맹점명이 너무 모호하면 sub는 null, confidence는 low
- **신규 카테고리(isNewMajor: true)에는 sub: null 고정**. 사용자가 직접 태그 만들도록. 신규 sub 자동 제안 X.
- sub은 사용자 기존 태그 중에서만 매칭. 의미 가까운 기존 태그 없으면 null.
- 출력 items 순서는 입력 순서와 동일

한국 가맹점 분류 가이드:
- 카페: 스타벅스/투썸/이디야/메가커피/파스쿠찌/할리스/공차
- 편의점: GS25/CU/세븐일레븐/이마트24/미니스톱
- 마트: 이마트/홈플러스/롯데마트/코스트코/노브랜드
- 음식점/식비: 배달의민족/요기요/쿠팡이츠/일반 식당명/한돈/김밥/칼국수/PC방의 식음료
- 주유: 현대오일뱅크/SK엔크린/GS칼텍스/S-Oil/희성석유
- 통신/구독: SKT/KT/LG U+/넷플릭스/디즈니플러스/유튜브 프리미엄/티빙/CLAUDE.AI/ANTHROPIC
- 게임: 넥슨/스팀/플레이스테이션/엑스박스/카카오게임즈
- 교통: 카카오택시/티머니/모바일티머니/RAILWAY/SRT/KTX/지하철
- 쇼핑: 쿠팡/네이버페이/PAYCO/올리브영/무신사
- PC방: PC/크라우드PC/도도PC
- 자동차: 정비/주차/주유 외 자동차 관련
- 의료: 약국/병원/치과/한의원

confidence:
- high: 잘 알려진 브랜드 (스타벅스, GS25 등)
- medium: 일반 가맹점인데 추측 가능 (지역명+업종)
- low: 정말 모를 때만`;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
};

const JSON_HEADERS = { ...CORS, "Content-Type": "application/json" };

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS });
  }

  try {
    const auth = req.headers.get("Authorization");
    if (!auth) return jsonError(401, "missing auth");

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) return jsonError(500, "ANTHROPIC_API_KEY not set");

    const body = await req.json().catch(() => ({}));
    const mode: string | undefined = body?.mode;

    const client = new Anthropic({ apiKey });

    if (mode === "parse-sheet") return handleParseSheet(body);
    if (mode === "mapping") return await handleMapping(client, body);
    if (mode === "classify") return await handleClassify(client, body);
    return jsonError(400, "invalid mode (expected 'parse-sheet', 'mapping', or 'classify')");
  } catch (e) {
    return jsonError(500, String(e));
  }
});

async function handleMapping(client: Anthropic, body: any): Promise<Response> {
  // 클라이언트가 파일 상단 row 10~12개를 firstRows로 통째로 보냄.
  // (어느 row가 헤더인지 모르고 보냄 — AI가 headerRowIndex로 알려줌)
  const firstRows: string[][] = body?.firstRows ?? [];
  if (!Array.isArray(firstRows) || firstRows.length === 0) {
    return jsonError(400, "firstRows (string[][]) required");
  }

  const userPrompt = [
    `파일 상단 ${firstRows.length}개 row (헤더가 어느 row인지 추정해주세요):`,
    firstRows
      .map((r, i) => `row[${i}]: ${r.join(" | ")}`)
      .join("\n"),
  ].join("\n");

  const message = await client.messages.create({
    model: "claude-opus-4-7",
    max_tokens: 800,
    system: [
      { type: "text", text: MAPPING_SYSTEM, cache_control: { type: "ephemeral" } },
    ],
    messages: [
      { role: "user", content: userPrompt },
    ],
  });

  const text = message.content
    .filter((b: any) => b.type === "text")
    .map((b: any) => b.text)
    .join("");
  const raw = extractJson(text);
  if (raw == null) {
    return jsonError(502, "AI response was not valid JSON");
  }

  let mapping: any;
  try {
    mapping = JSON.parse(raw);
  } catch {
    return jsonError(502, "AI response was not valid JSON");
  }

  // 휴리스틱 보정: AI가 headerRowIndex를 누락하거나 0으로 줬는데 실제로는
  // row[0]이 제목 row(채워진 셀 비율 < 30%)면 row[1]을 헤더로 강제.
  mapping = fixHeaderRow(mapping, firstRows);

  return new Response(
    JSON.stringify({ mapping, usage: message.usage }),
    { headers: JSON_HEADERS }
  );
}

function fixHeaderRow(mapping: any, firstRows: string[][]): any {
  const declared = typeof mapping.headerRowIndex === "number"
    ? mapping.headerRowIndex
    : 0;
  // row[0]이 진짜 헤더로 보일 때만 그대로. 아니면 첫 "꽉 찬" row를 헤더로.
  const fillRatio = (r: string[]) => {
    if (r.length === 0) return 0;
    const filled = r.filter((c) => c && c.trim().length > 0).length;
    return filled / r.length;
  };
  // 후보: 셀 채움 비율 50% 이상 + 모든 셀이 짧은 텍스트(컬럼명) 인 row.
  const looksHeader = (r: string[]) => {
    if (fillRatio(r) < 0.5) return false;
    // 헤더는 보통 짧고 숫자/날짜 패턴이 많지 않음
    let numericLike = 0;
    for (const c of r) {
      const t = (c ?? "").trim();
      if (!t) continue;
      if (/^[\d,.\-+₩원\s]+$/.test(t) || /^\d{4}[-./]\d{1,2}/.test(t)) {
        numericLike++;
      }
    }
    return numericLike <= 1;
  };
  // declared가 합리적이면(row가 looksHeader true) 그대로 쓰되, 아니면 보정.
  if (
    declared >= 0 &&
    declared < firstRows.length &&
    looksHeader(firstRows[declared])
  ) {
    return mapping;
  }
  for (let i = 0; i < Math.min(firstRows.length, 4); i++) {
    if (looksHeader(firstRows[i])) {
      return { ...mapping, headerRowIndex: i };
    }
  }
  return mapping;
}

async function handleClassify(client: Anthropic, body: any): Promise<Response> {
  const merchants: string[] = body?.merchants ?? [];
  const userMajors: string[] = body?.userMajors ?? [];
  const userCategories: { major: string; sub: string }[] = body?.userCategories ?? [];

  if (!Array.isArray(merchants) || merchants.length === 0) {
    return jsonError(400, "merchants (string[]) required");
  }

  const catList = userCategories.length > 0
    ? userCategories.map((c) => `${c.major}/${c.sub}`).join(", ")
    : "(없음)";

  const userPrompt = [
    "사용자 기존 카테고리:",
    userMajors.length > 0 ? userMajors.join(", ") : "(없음)",
    "",
    "사용자 기존 태그 (카테고리/태그 형식):",
    catList,
    "",
    `분류할 가맹점 (${merchants.length}건):`,
    merchants.map((m, i) => `[${i}] ${m}`).join("\n"),
  ].join("\n");

  const message = await client.messages.create({
    model: "claude-opus-4-7",
    max_tokens: 4000,
    system: [
      { type: "text", text: CLASSIFY_SYSTEM, cache_control: { type: "ephemeral" } },
    ],
    messages: [
      { role: "user", content: userPrompt },
    ],
  });

  const text = message.content
    .filter((b: any) => b.type === "text")
    .map((b: any) => b.text)
    .join("");
  const raw = extractJson(text);
  if (raw == null) {
    return jsonError(502, "AI response was not valid JSON");
  }

  let classification: any;
  try {
    classification = JSON.parse(raw);
  } catch {
    return jsonError(502, "AI response was not valid JSON");
  }

  // 신규 카테고리(isNewMajor: true)면 sub은 무조건 null로 강제.
  // 신규 카테고리에 신규 태그까지 자동 추가하면 사용자 카테고리가 너무 어수선해짐.
  if (Array.isArray(classification?.items)) {
    for (const it of classification.items) {
      if (it && it.isNewMajor === true) {
        it.sub = null;
        it.isNewSub = false;
      }
    }
  }

  return new Response(
    JSON.stringify({ classification, usage: message.usage }),
    { headers: JSON_HEADERS }
  );
}

// xls(BIFF)·xlsx 같은 시트 포맷을 SheetJS로 파싱해서 headers + rows 반환.
// 클라이언트가 base64 인코딩된 파일을 보냄. 한국 카드사 .xls(구버전)는
// 클라이언트의 excel 패키지가 못 읽으니 서버 fallback으로 사용.
function handleParseSheet(body: any): Response {
  const fileBase64: string | undefined = body?.fileBase64;
  if (typeof fileBase64 !== "string" || fileBase64.length === 0) {
    return jsonError(400, "fileBase64 required");
  }
  const cleaned = fileBase64.replace(/\s/g, "");
  let bytes: Uint8Array;
  try {
    const bin = atob(cleaned);
    bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  } catch {
    return jsonError(400, "fileBase64 decode failed");
  }

  // 카드사 명세서는 보통 수십~수백 KB. 안전하게 4MB 제한.
  if (bytes.length > 4 * 1024 * 1024) {
    return jsonError(413, "파일이 너무 커요 (4MB 미만)");
  }

  let wb: any;
  try {
    wb = XLSX.read(bytes, { type: "array", cellDates: true, raw: false });
  } catch (e) {
    return jsonError(400, `시트 파싱 실패: ${e}`);
  }

  if (!wb.SheetNames || wb.SheetNames.length === 0) {
    return jsonError(400, "시트가 없어요");
  }

  const sheet = wb.Sheets[wb.SheetNames[0]];
  const raw: any[][] = XLSX.utils.sheet_to_json(sheet, {
    header: 1,
    defval: "",
    blankrows: false,
  });

  const stringify = (cell: any): string => {
    if (cell == null) return "";
    if (cell instanceof Date) {
      const y = cell.getUTCFullYear().toString().padStart(4, "0");
      const m = (cell.getUTCMonth() + 1).toString().padStart(2, "0");
      const d = cell.getUTCDate().toString().padStart(2, "0");
      return `${y}-${m}-${d}`;
    }
    return String(cell);
  };

  const allRows = raw
    .map((r) => r.map(stringify))
    .filter((r) => r.some((c) => c.trim().length > 0));
  if (allRows.length === 0) return jsonError(400, "데이터 행이 없어요");

  // trailing 빈 컬럼 제거.
  let maxCol = 0;
  for (const r of allRows) {
    for (let i = r.length - 1; i >= 0; i--) {
      if (r[i].trim().length > 0) {
        if (i + 1 > maxCol) maxCol = i + 1;
        break;
      }
    }
  }
  const trimmed = allRows.map((r) =>
    r.length > maxCol ? r.slice(0, maxCol) : r
  );

  const headers = trimmed[0];
  const rows = trimmed.slice(1);

  return new Response(
    JSON.stringify({ headers, rows, sheetName: wb.SheetNames[0] }),
    { headers: JSON_HEADERS }
  );
}

// 응답 텍스트에서 첫 { 부터 짝이 맞는 } 까지 JSON 객체만 추출.
// 모델이 ```json 같은 코드블록을 감싸거나 앞뒤 설명을 덧붙여도 안전.
function extractJson(text: string): string | null {
  const start = text.indexOf("{");
  if (start === -1) return null;
  let depth = 0;
  let inStr = false;
  let escape = false;
  for (let i = start; i < text.length; i++) {
    const c = text[i];
    if (inStr) {
      if (escape) {
        escape = false;
      } else if (c === "\\") {
        escape = true;
      } else if (c === '"') {
        inStr = false;
      }
      continue;
    }
    if (c === '"') {
      inStr = true;
    } else if (c === "{") {
      depth++;
    } else if (c === "}") {
      depth--;
      if (depth === 0) return text.substring(start, i + 1);
    }
  }
  return null;
}

function jsonError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: JSON_HEADERS,
  });
}
