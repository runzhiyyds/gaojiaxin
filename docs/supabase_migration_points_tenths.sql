-- 心意值一位小数：内部以十分之一为单位存储（1 单位 = 0.1 心意值）
-- 执行前请备份。执行后历史数据将变为十倍（如 5 → 50），展示时除以 10 为 5.0。

-- 积分记录：心意值改为十分之一单位
update public.point_records set points = points * 10 where points > 0 and points < 1000;

-- 商城商品：所需心意值改为十分之一单位
update public.mall_goods set points_required = points_required * 10 where points_required > 0 and points_required < 100000;

-- 兑换记录：消耗心意值改为十分之一单位
update public.exchange_records set points_spent = points_spent * 10 where points_spent > 0 and points_spent < 100000;

-- 定期存款本金改为十分之一单位（若表存在且存的是“心意值”）
do $$
begin
  if exists (select 1 from information_schema.tables where table_schema = 'public' and table_name = 'point_deposits') then
    update public.point_deposits set principal = principal * 10 where principal > 0 and principal < 100000;
  end if;
end$$;
