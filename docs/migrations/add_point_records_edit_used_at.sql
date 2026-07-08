-- 为积分记录增加「一次编辑/删除」标记：已有记录 edit_used_at 为 null 表示仍可使用一次机会
alter table public.point_records
  add column if not exists edit_used_at timestamptz;

comment on column public.point_records.edit_used_at is '非空表示已使用一次编辑或删除机会，不可再改';
