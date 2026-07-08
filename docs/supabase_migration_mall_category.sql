-- 商城商品增加品类，便于分类展示与预设
alter table public.mall_goods
  add column if not exists category text;

comment on column public.mall_goods.category is '品类，如：知识付费、科技赋能、虚拟类、书籍类、礼物等';
