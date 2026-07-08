-- 爱的维度标签：为积分/心意项目与记录增加 love_dimension 字段
-- 在 Supabase SQL Editor 中执行本脚本

do $$
begin
  if not exists (
    select 1
    from pg_type
    where typname = 'love_dimension'
  ) then
    create type love_dimension as enum (
      'care',
      'companionship',
      'understanding',
      'growth',
      'responsibility',
      'ritual',
      'passion'
    );
  end if;
end$$;

alter table public.point_items
  add column if not exists love_dimension love_dimension;

alter table public.point_records
  add column if not exists love_dimension love_dimension;

