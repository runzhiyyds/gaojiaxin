-- 可选：启用 Realtime 后，表数据变更会推送到客户端，列表可实时刷新
-- 在 Supabase SQL Editor 中执行（若报错已存在可忽略）

alter publication supabase_realtime add table public.point_records;
alter publication supabase_realtime add table public.point_items;
alter publication supabase_realtime add table public.mall_goods;
alter publication supabase_realtime add table public.exchange_records;
