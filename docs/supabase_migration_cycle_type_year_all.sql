-- 统计周期与 TAB2（月/年/历史所有）对齐：为 cycle_type 增加 year、all
-- 在 Supabase SQL Editor 中执行（仅需执行一次，重复执行会报“值已存在”可忽略）

alter type public.cycle_type add value 'year';
alter type public.cycle_type add value 'all';
