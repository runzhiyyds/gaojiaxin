-- 积分项目增加「默认项目」标记，用于「记一笔」一键记录
-- 在 Supabase SQL Editor 中执行

ALTER TABLE public.point_items
  ADD COLUMN IF NOT EXISTS is_default boolean NOT NULL DEFAULT false;

COMMENT ON COLUMN public.point_items.is_default IS '为 true 时，记一笔一键使用该项目';
