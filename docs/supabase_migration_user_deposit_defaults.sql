-- 用户「新奖励默认存入」偏好：选好后对方给的积分自动进入该定期
-- 在 Supabase SQL Editor 中执行

CREATE TABLE IF NOT EXISTS public.user_deposit_defaults (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  couple_space_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE CASCADE,
  product_type text,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, couple_space_id)
);

COMMENT ON TABLE public.user_deposit_defaults IS '新奖励默认存入：product_type 为空表示不自动存，否则对方记的积分自动存入该定期';

ALTER TABLE public.user_deposit_defaults ENABLE ROW LEVEL SECURITY;

CREATE POLICY "User deposit defaults: CRUD for own space"
  ON public.user_deposit_defaults FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.couple_spaces cs
      WHERE cs.id = user_deposit_defaults.couple_space_id
      AND (cs.user_a_id = auth.uid() OR cs.user_b_id = auth.uid())
    )
  );
