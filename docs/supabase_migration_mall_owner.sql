-- 商城商品归属：每个商品属于一个用户（该用户的「积分商城」），对方用积分在此兑换
-- 在 Supabase SQL Editor 中执行

-- 1. 添加 owner_id（先可空，便于对已有数据回填）
alter table public.mall_goods
  add column if not exists owner_id uuid references auth.users(id) on delete cascade;

-- 2. 回填：已有商品归属到该空间创建者 user_a_id
update public.mall_goods mg
set owner_id = cs.user_a_id
from public.couple_spaces cs
where mg.couple_space_id = cs.id
  and mg.owner_id is null;

-- 3. 若仍有空（理论上不该有），归属到空间内任意用户
update public.mall_goods mg
set owner_id = coalesce(
  (select cs.user_a_id from public.couple_spaces cs where cs.id = mg.couple_space_id),
  (select cs.user_b_id from public.couple_spaces cs where cs.id = mg.couple_space_id)
)
where mg.owner_id is null;

-- 4. 设为必填
alter table public.mall_goods
  alter column owner_id set not null;

-- 5. RLS 已有「同空间可 CRUD」，无需改；按 owner 筛选在应用层做即可
