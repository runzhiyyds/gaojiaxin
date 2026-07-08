-- 兑换记录「已满足」状态：对方点击「满足TA」后标记
-- 在 Supabase SQL Editor 中执行

alter table public.exchange_records
  add column if not exists fulfilled_at timestamptz default null;

alter table public.exchange_records
  add column if not exists fulfilled_by uuid references auth.users(id) on delete set null;

comment on column public.exchange_records.fulfilled_at is '对方点击「满足TA」的时间';
comment on column public.exchange_records.fulfilled_by is '点击「满足TA」的用户 id';
