-- 가계부 Supabase 스키마 (참고용 스냅샷 — 비완전/NON-AUTHORITATIVE).
-- 실제 DB는 mcp__supabase__apply_migration 으로 누적 관리하며, 이 파일은
-- 신규 환경 1회 부트스트랩이나 구조 파악용이다. 아래 핵심 테이블 일부만 담겨
-- 있고 후속 마이그레이션은 반영돼 있지 않다 — 정확한 최신 구조는 Supabase
-- 마이그레이션 히스토리를 source of truth로 삼을 것.
--
-- ⚠️ 이 파일에 *아직 반영되지 않은* 프로덕션 객체 (CLAUDE.md 기준):
--   테이블:
--     • ai_insights          PK(user_id, month), content text, generated_at
--     • fixed_apply_log       PK(user_id, fixed_id, month)  -- 정기거래 중복적용 차단
--     • transaction_templates 거래 템플릿(이름/type/금액/카테고리/계좌·카드 등)
--     • ai_rate_limits        (user_id, bucket, hour) AI 호출 쿼터
--   함수/RPC:
--     • seed_default_data_for_new_user  -- auth.users INSERT 시 기본 데이터 시드
--     • tx_invalidate_ai_insights        -- 거래 변경 시 해당 월 AI 캐시 무효화
--     • check_email_exists(p_email)      -- 가입 실시간 중복 체크
--     • delete_my_account()              -- 본인 계정 + CASCADE 삭제
--     • consume_ai_quota(...)            -- AI 호출 쿼터 소진(SECURITY DEFINER)
--   ※ 위 객체의 정확한 DDL은 이 스냅샷에서 검증 불가 — 마이그레이션 참조.

-- 1) 테이블

create table majors (
  user_id uuid not null references auth.users(id) on delete cascade,
  major text not null,
  sort_order int not null default 0,
  -- 'expense' (지출 카테고리) | 'income' (수입 카테고리).
  type text not null default 'expense' check (type in ('expense','income')),
  primary key (user_id, major)
);
create index idx_majors_user_type on majors(user_id, type);

create table categories (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  major text not null,
  sub text not null,
  sort_order int not null default 0,
  unique (user_id, major, sub)
);

create table budgets (
  user_id uuid not null references auth.users(id) on delete cascade,
  major text not null,
  monthly_amount bigint not null default 0,
  updated_at timestamptz default now(),
  primary key (user_id, major)
);

-- accounts: 사용자별 계좌(현금/카드/예적금 등). 자산 흐름의 기본 단위.
create table accounts (
  id              bigserial primary key,
  user_id         uuid not null references auth.users(id) on delete cascade,
  name            text not null,
  -- 신용카드는 계좌가 아닌 별도 entity(cards, 추후)로 분리.
  type            text not null check (type in
                    ('checking','cash','savings','investment','other')),
  initial_balance bigint not null default 0,
  sort_order      int not null default 0,
  active          int not null default 1,
  created_at      timestamptz not null default now(),
  updated_at      timestamptz not null default now(),
  unique (user_id, name)
);
create index idx_accounts_user_active on accounts(user_id, active desc, sort_order);

-- 신용카드 entity. 자산(계좌)과 분리 — 사용 시점엔 자산 영향 X,
-- 결제일에 linked_account에서 한 번에 차감되는 card_payment 거래로 정산.
create table cards (
  id                  bigserial primary key,
  user_id             uuid not null references auth.users(id) on delete cascade,
  name                text not null,
  payment_day         int not null check (payment_day between 1 and 31),
  linked_account_id   bigint not null references accounts(id) on delete restrict,
  -- 사용 마감일 (이날 이후 사용분은 다음 달 결제). 모르면 null.
  statement_close_day int check (statement_close_day between 1 and 31),
  sort_order          int not null default 0,
  active              int not null default 1,
  created_at          timestamptz not null default now(),
  updated_at          timestamptz not null default now(),
  unique (user_id, name)
);
create index idx_cards_user_active on cards(user_id, active desc, sort_order);

create table transactions (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  date text not null,
  card text,
  merchant text,
  amount bigint not null,
  major_category text not null,
  sub_category text,
  memo text,
  is_fixed int not null default 0,
  -- expense (account): account_id만
  -- expense (card 사용): card_id만 (자산 영향 X, 카드 부채 +)
  -- income: account_id만
  -- transfer: from/to_account_id 둘 다 (서로 다른 계좌)
  -- card_payment: from_account_id (linked) + card_id (정산 대상)
  account_id      bigint references accounts(id) on delete restrict,
  from_account_id bigint references accounts(id) on delete restrict,
  to_account_id   bigint references accounts(id) on delete restrict,
  card_id         bigint references cards(id) on delete restrict,
  type            text not null default 'expense'
    check (type in ('expense','income','transfer','card_payment')),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  constraint tx_account_consistency check (
    (type = 'expense' and from_account_id is null and to_account_id is null
     and ((account_id is not null and card_id is null)
       or (account_id is null and card_id is not null)))
    or
    (type = 'income' and account_id is not null
     and from_account_id is null and to_account_id is null and card_id is null)
    or
    (type = 'transfer' and from_account_id is not null and to_account_id is not null
     and from_account_id <> to_account_id
     and account_id is null and card_id is null)
    or
    (type = 'card_payment' and from_account_id is not null and card_id is not null
     and account_id is null and to_account_id is null)
  )
);
create index idx_tx_user_date on transactions(user_id, date);
create index idx_tx_user_major on transactions(user_id, major_category);
create index idx_tx_account on transactions(user_id, account_id);
create index idx_tx_from on transactions(user_id, from_account_id) where from_account_id is not null;
create index idx_tx_to on transactions(user_id, to_account_id) where to_account_id is not null;
create index idx_tx_card on transactions(user_id, card_id) where card_id is not null;

create table fixed_expenses (
  id bigserial primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  major text not null,
  sub text,
  amount bigint not null default 0,
  card text,
  day_of_month int not null default 1,
  active int not null default 1,
  memo text,
  sort_order int not null default 0,
  -- 결제수단 — 둘 중 하나만 (XOR). 정기수입은 항상 account_id.
  account_id bigint references accounts(id) on delete restrict,
  card_id    bigint references cards(id) on delete restrict,
  type text not null default 'expense' check (type in ('expense','income')),
  created_at timestamptz default now(),
  updated_at timestamptz default now(),
  constraint fx_account_or_card check (
    (type = 'income' and account_id is not null and card_id is null)
    or
    (type = 'expense' and (
      (account_id is not null and card_id is null)
      or (account_id is null and card_id is not null)
    ))
  )
);
create index idx_fx_user_type on fixed_expenses(user_id, type);
create index idx_fx_card on fixed_expenses(user_id, card_id) where card_id is not null;

-- 2) Row Level Security: 자기 데이터만 읽고 쓰게

alter table majors enable row level security;
alter table categories enable row level security;
alter table budgets enable row level security;
alter table accounts enable row level security;
alter table cards enable row level security;
alter table transactions enable row level security;
alter table fixed_expenses enable row level security;

create policy "own majors" on majors for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own categories" on categories for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own budgets" on budgets for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own accounts" on accounts for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own cards" on cards for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own transactions" on transactions for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

create policy "own fixed_expenses" on fixed_expenses for all
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- 3) updated_at 자동 갱신 트리거

create or replace function set_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger tx_set_updated_at before update on transactions
  for each row execute function set_updated_at();

create trigger fx_set_updated_at before update on fixed_expenses
  for each row execute function set_updated_at();

create trigger bg_set_updated_at before update on budgets
  for each row execute function set_updated_at();

create trigger ac_set_updated_at before update on accounts
  for each row execute function set_updated_at();

create trigger cd_set_updated_at before update on cards
  for each row execute function set_updated_at();
