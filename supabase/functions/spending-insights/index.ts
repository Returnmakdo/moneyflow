// Supabase Edge Function — 가계부 소비 패턴 분석.
// 클라이언트는 사용자 JWT만 들고 호출하고, Anthropic API 키는 서버 환경변수
// (ANTHROPIC_API_KEY)로만 둠. 결과는 ai_insights 테이블에 캐시되고 거래
// 변경 시 트리거가 자동 무효화함.
//
// 배포: mcp__supabase__deploy_edge_function 으로 이 파일 통째로 업로드.
// (Supabase CLI 없이도 MCP 한 번으로 배포 가능)

import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import Anthropic from "npm:@anthropic-ai/sdk@0.73.0";
import { createClient } from "jsr:@supabase/supabase-js@2";

const SYSTEM_PROMPT = `당신은 친근한 한국 가계부 코치입니다. 사용자의 한 달 지출 데이터를 보고 패턴과 특이점을 짚어줘요.

출력 구조:
1. 맨 처음에 # 한 줄 요약 — 사실/숫자 중심으로 짧고 압축적으로.
   - 좋은 예: "이번 달 240만원 · 전월 -57만원", "지출 240만원, 차량정비 30만원이 컸음"
   - 나쁜 예: "지난달보다 57만원 줄어서 240만원 썼네" (회화체는 본문용), "이번 달 분석 결과"
   - 규칙: 회화체 어미(~네, ~야, ~았어) 쓰지 말고 명사 종결/짧은 평서문. 길이 25자 내외.
2. 빈 줄 후 본문 ## 섹션 2~3개 (의미 있는 것만 골라서). 본문은 친근체 그대로.

섹션 (정확히 다음 4개 이름만 사용. 의미 있는 것만 골라서, 보통 3~4개):
- ## 이번 달 요약  → 총액, 전월 대비, 고정/변동, 수입·저축률(데이터 있을 때)을 한 문단으로
- ## 눈에 띄는 패턴  → 카테고리 쏠림, 자주 간 가맹점, 주말·평일 차이, 이상치 거래를 근거 있게
- ## 예산 체크  → 초과되거나 임박한 카테고리가 있을 때만 (예산 데이터 없으면 생략)
- ## 다음 달 제안  → 구체적인 한 가지 행동 + 왜 효과적인지 근거 + 예상 효과 (3~4문장으로 풍부하게, 일반론 X)

**수입 데이터 사용 규칙**:
- 입력에 "## 수입 흐름" 섹션이 있으면 그 숫자만 사용. 추정·창작 X.
- 수입 데이터는 "## 이번 달 요약" 한두 문장 + "## 다음 달 제안" 근거에서만 사용. 다른 섹션엔 끌어 쓰지 마.
- 수입 데이터 자체가 없으면(섹션 부재) 수입·저축률 일절 언급 X.
- 저축률 음수면 "적자"로 표현. 양수면 "흑자" 또는 "저축률 N%".

중요: ## 헤더 텍스트는 위 4개와 정확히 일치해야 해 (UI에서 매칭됨). 다른 이름 X.

스타일:
- 마크다운으로 작성. 친근한 반말 (~야, ~네, ~보자, ~았어)
- 간결하게. 본문 전체 5~7줄. 각 ## 섹션은 2~3줄 짧게.
- **각 문장 끝(마침표) 뒤에 반드시 줄바꿈을 넣어. 한 문장 = 한 줄.** 마침표 여러 개를 한 줄에 붙이지 마.
- 숫자는 '12만원' '1.2억' 식으로 깔끔히

볼드(**) 사용 규칙:
- 정말 메시지 핵심 1~3군데에만. 모든 숫자에 다 쓰면 시각이 평탄해져서 강조가 안 됨.
- 영어/숫자/% 같은 어구에만 적용해. 예: **-58만원**, **84%**, **600%**
- 한글 단어/조사에는 절대 쓰지 마. (한글 옆 ** 는 마크다운 파서가 처리 못해서 ** 가 그대로 노출됨)
- 한글에 강조 주고 싶으면 그냥 평문으로 쓰고 본문 흐름으로 강조해.
- ~~ (물결 두 개) 절대 쓰지 마. 취소선으로 렌더링됨 — 강조 의도라면 ** 만 사용.

규칙:
- 데이터에 없는 추측 금지
- 이상치 거래는 액수 + 가맹점으로 구체적으로
- 예산 데이터가 0이면 예산 섹션 생략
- 일반 잔소리 금지 ('절약하세요', '계획적 소비' 같은 클리셰)
- ## 섹션은 너무 잔소리스럽게 나누지 말고 한 흐름으로
- 자연스러운 한국어 표현 (조사·맞춤법 정확히)`;

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: CORS });
  }

  const headers = { ...CORS, "Content-Type": "application/json" };

  try {
    const auth = req.headers.get("Authorization");
    if (!auth) {
      return new Response(JSON.stringify({ error: "missing auth" }), {
        status: 401,
        headers,
      });
    }

    const body = await req.json().catch(() => ({}));
    const month: string | undefined = body?.month;
    const force: boolean = body?.force === true;
    if (!month || !/^\d{4}-\d{2}$/.test(month)) {
      return new Response(JSON.stringify({ error: "invalid month" }), {
        status: 400,
        headers,
      });
    }

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_ANON_KEY")!,
      { global: { headers: { Authorization: auth } } }
    );

    // 1단계: 캐시 확인 (force=false일 때만).
    if (!force) {
      const cached = await supabase
        .from("ai_insights")
        .select("content, generated_at")
        .eq("month", month)
        .maybeSingle();
      if (cached.data?.content) {
        return new Response(JSON.stringify({
          insight: cached.data.content,
          cached: true,
          generatedAt: cached.data.generated_at,
        }), { headers });
      }
    }

    // 2단계: 데이터 fetch (이번달 거래 + 지난달 거래 + 예산).
    const [y, m] = month.split("-").map(Number);
    const prevDate = new Date(y, m - 2, 1);
    const prevMonth = `${prevDate.getFullYear()}-${String(prevDate.getMonth() + 1).padStart(2, "0")}`;

    const [thisRes, prevRes, budgetsRes] = await Promise.all([
      supabase.from("transactions")
        .select("date,major_category,sub_category,merchant,amount,is_fixed,memo,account_id,type")
        .gte("date", `${month}-01`).lte("date", `${month}-31`),
      supabase.from("transactions")
        .select("amount,major_category,is_fixed,type")
        .gte("date", `${prevMonth}-01`).lte("date", `${prevMonth}-31`),
      supabase.from("budgets")
        .select("major,monthly_amount"),
    ]);

    if (thisRes.error) {
      return new Response(JSON.stringify({ error: thisRes.error.message }), {
        status: 500, headers,
      });
    }

    // 지출 분석은 expense에만, 저축률 계산용으로 income도 별도 집계.
    const allThis = thisRes.data || [];
    const allPrev = prevRes.data || [];
    const txs = allThis.filter((t) => t.type === 'expense');
    const prevTxs = allPrev.filter((t) => t.type === 'expense');
    const incomeTxs = allThis.filter((t) => t.type === 'income');
    const prevIncomeTxs = allPrev.filter((t) => t.type === 'income');
    const budgets = budgetsRes.data || [];

    if (txs.length === 0) {
      return new Response(JSON.stringify({
        insight: "## 거래가 없어\n\n이번 달 거래를 추가하면 분석해줄게.",
      }), { headers });
    }

    // 3단계: 집계.
    const total = txs.reduce((s, t) => s + Number(t.amount), 0);
    const fixedTotal = txs.filter((t) => t.is_fixed === 1).reduce((s, t) => s + Number(t.amount), 0);
    const variableTotal = total - fixedTotal;
    const prevTotal = prevTxs.reduce((s, t) => s + Number(t.amount), 0);

    // 카테고리별 (전체 + 변동비만).
    const byMajor: Record<string, number> = {};
    const byMajorVar: Record<string, number> = {};
    for (const t of txs) {
      const a = Number(t.amount);
      byMajor[t.major_category] = (byMajor[t.major_category] || 0) + a;
      if (t.is_fixed !== 1) {
        byMajorVar[t.major_category] = (byMajorVar[t.major_category] || 0) + a;
      }
    }
    // 지난달 카테고리별 (전월 대비 변화 계산용).
    const prevByMajor: Record<string, number> = {};
    for (const t of prevTxs) {
      prevByMajor[t.major_category] =
        (prevByMajor[t.major_category] || 0) + Number(t.amount);
    }

    // 태그별 (변동비만).
    const bySub: Record<string, { total: number; count: number }> = {};
    for (const t of txs) {
      if (t.is_fixed === 1) continue;
      const key = `${t.major_category}/${t.sub_category}`;
      if (!bySub[key]) bySub[key] = { total: 0, count: 0 };
      bySub[key].total += Number(t.amount);
      bySub[key].count += 1;
    }

    // 가맹점별.
    const byMerchant: Record<string, { total: number; count: number }> = {};
    for (const t of txs) {
      if (!t.merchant) continue;
      if (!byMerchant[t.merchant]) byMerchant[t.merchant] = { total: 0, count: 0 };
      byMerchant[t.merchant].total += Number(t.amount);
      byMerchant[t.merchant].count += 1;
    }

    // 평일 vs 주말 (변동비만).
    let weekdayTotal = 0;
    let weekendTotal = 0;
    let weekdayCount = 0;
    let weekendCount = 0;
    for (const t of txs) {
      if (t.is_fixed === 1) continue;
      const d = new Date(t.date + "T00:00:00");
      const dow = d.getDay(); // 0=Sun, 6=Sat
      const a = Number(t.amount);
      if (dow === 0 || dow === 6) {
        weekendTotal += a;
        weekendCount += 1;
      } else {
        weekdayTotal += a;
        weekdayCount += 1;
      }
    }

    // 이상치: 변동비 거래 중 평균의 5배 이상이면서 전체의 5% 이상이고
    // 5만원 이상인 큰 한 건 (가전 구매, 차량 정비 같은 큰 단발성 지출).
    const variableTxs = txs.filter((t) => t.is_fixed !== 1);
    const avgVar = variableTxs.length > 0
      ? variableTotal / variableTxs.length : 0;
    const outliers = variableTxs
      .filter((t) => {
        const a = Number(t.amount);
        return a >= avgVar * 5 && a >= total * 0.05 && a >= 50000;
      })
      .sort((a, b) => Number(b.amount) - Number(a.amount))
      .slice(0, 3);

    const won = (n: number) => `${Math.round(n).toLocaleString("ko-KR")}원`;

    const topMajors = Object.entries(byMajor).sort((a, b) => b[1] - a[1]);
    const topSubs = Object.entries(bySub)
      .sort((a, b) => b[1].total - a[1].total).slice(0, 10);
    const topMerchants = Object.entries(byMerchant)
      .sort((a, b) => b[1].total - a[1].total).slice(0, 8);

    // 카테고리별 전월 대비 변화 (절대값 큰 변화 상위 5개).
    const allCats = new Set([...Object.keys(byMajor), ...Object.keys(prevByMajor)]);
    const swings: { major: string; cur: number; prev: number; diff: number }[] = [];
    for (const c of allCats) {
      const cur = byMajor[c] || 0;
      const prev = prevByMajor[c] || 0;
      swings.push({ major: c, cur, prev, diff: cur - prev });
    }
    swings.sort((a, b) => Math.abs(b.diff) - Math.abs(a.diff));
    const topSwings = swings.filter((s) => Math.abs(s.diff) >= 30000).slice(0, 5);

    // 예산 대비 (변동비 기준). 예산 0인 카테고리는 추적 안 함.
    const budgetCheck: { major: string; budget: number; spent: number; pct: number }[] = [];
    for (const b of budgets) {
      const limit = Number(b.monthly_amount);
      if (limit <= 0) continue;
      const spent = byMajorVar[b.major] || 0;
      const pct = Math.round((spent / limit) * 100);
      budgetCheck.push({ major: b.major, budget: limit, spent, pct });
    }
    budgetCheck.sort((a, b) => b.pct - a.pct);

    const diffStr = prevTotal > 0
      ? `지난달 ${won(prevTotal)} → 이번달 ${won(total)} (${total - prevTotal >= 0 ? "+" : ""}${won(total - prevTotal)})`
      : `지난달 데이터 없음, 이번달 ${won(total)}`;

    // 수입 집계 — 이번 달 수입 0이면 섹션 자체를 안 보냄(시스템 프롬프트가
    // 수입 미언급으로 동작). 0보다 크면 저축률·흑자 분석에 사용.
    const incomeTotal = incomeTxs.reduce((s, t) => s + Number(t.amount), 0);
    const prevIncomeTotal = prevIncomeTxs.reduce((s, t) => s + Number(t.amount), 0);
    const netSaving = incomeTotal - total;
    const savingRate = incomeTotal > 0
      ? Math.round((netSaving / incomeTotal) * 100)
      : null;

    const sections: string[] = [];
    sections.push(`# ${month} 지출 데이터\n\n${diffStr}\n- 고정비: ${won(fixedTotal)}\n- 변동비: ${won(variableTotal)}\n- 거래 수: ${txs.length}건`);

    if (incomeTotal > 0) {
      const incLines: string[] = [];
      incLines.push(`- 이번 달 수입: ${won(incomeTotal)}`);
      if (prevIncomeTotal > 0) {
        const incDiff = incomeTotal - prevIncomeTotal;
        incLines.push(`- 지난 달 수입: ${won(prevIncomeTotal)} (${incDiff >= 0 ? "+" : ""}${won(incDiff)})`);
      }
      incLines.push(`- 순저축(수입 - 지출): ${won(netSaving)}`);
      if (savingRate != null) {
        incLines.push(`- 저축률: ${savingRate}%${savingRate < 0 ? " (적자)" : ""}`);
      }
      sections.push(`## 수입 흐름\n${incLines.join("\n")}`);
    }

    sections.push(`## 카테고리별 (전체)\n${topMajors.map(([k, v]) => `- ${k}: ${won(v)}`).join("\n")}`);

    if (topSwings.length > 0) {
      sections.push(`## 전월 대비 주요 변화\n${topSwings.map((s) => `- ${s.major}: ${won(s.prev)} → ${won(s.cur)} (${s.diff >= 0 ? "+" : ""}${won(s.diff)})`).join("\n")}`);
    }

    sections.push(`## 변동비 태그 TOP\n${topSubs.map(([k, v]) => `- ${k}: ${won(v.total)} (${v.count}건)`).join("\n")}`);

    sections.push(`## 자주 간 가맹점\n${topMerchants.map(([k, v]) => `- ${k}: ${won(v.total)} (${v.count}건)`).join("\n")}`);

    if (weekdayCount + weekendCount > 0) {
      const weekdayAvg = weekdayCount > 0 ? weekdayTotal / weekdayCount : 0;
      const weekendAvg = weekendCount > 0 ? weekendTotal / weekendCount : 0;
      sections.push(`## 평일 vs 주말 (변동비)\n- 평일: 총 ${won(weekdayTotal)}, ${weekdayCount}건, 건당 ${won(weekdayAvg)}\n- 주말: 총 ${won(weekendTotal)}, ${weekendCount}건, 건당 ${won(weekendAvg)}`);
    }

    if (outliers.length > 0) {
      sections.push(`## 이상치 거래 (변동비 평균 ${won(avgVar)} 대비 큰 건)\n${outliers.map((t) => `- ${t.date} ${t.merchant ?? "(가맹점 없음)"} / ${t.major_category}: ${won(Number(t.amount))}`).join("\n")}`);
    }

    if (budgetCheck.length > 0) {
      sections.push(`## 예산 대비 (변동비 기준)\n${budgetCheck.map((b) => `- ${b.major}: ${won(b.spent)} / ${won(b.budget)} = ${b.pct}%`).join("\n")}`);
    }

    sections.push(`\n위 데이터로 이번 달 소비 패턴 분석해줘.`);

    const userPrompt = sections.join("\n\n");

    const apiKey = Deno.env.get("ANTHROPIC_API_KEY");
    if (!apiKey) {
      return new Response(JSON.stringify({ error: "ANTHROPIC_API_KEY not set" }), {
        status: 500, headers,
      });
    }

    const client = new Anthropic({ apiKey });

    const message = await client.messages.create({
      model: "claude-opus-4-7",
      max_tokens: 1500,
      thinking: { type: "adaptive" },
      system: [
        {
          type: "text",
          text: SYSTEM_PROMPT,
          cache_control: { type: "ephemeral" },
        },
      ],
      messages: [{ role: "user", content: userPrompt }],
    });

    const text = message.content
      .filter((b: any) => b.type === "text")
      .map((b: any) => b.text)
      .join("\n");

    // 4단계: 캐시 저장 (upsert).
    // user_id는 ai_insights 테이블의 DEFAULT auth.uid() 로 자동 설정됨.
    await supabase.from("ai_insights").upsert({
      month,
      content: text,
      generated_at: new Date().toISOString(),
    }, { onConflict: "user_id,month" });

    return new Response(JSON.stringify({
      insight: text,
      cached: false,
      usage: message.usage,
    }), { headers });
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers,
    });
  }
});
