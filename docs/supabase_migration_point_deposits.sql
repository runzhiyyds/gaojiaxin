-- 积分存储（定期零存整取）：锁定部分兑换余额，到期付息，提前支取扣光利息
-- 在 Supabase SQL Editor 中执行

CREATE TABLE IF NOT EXISTS public.point_deposits (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  couple_space_id uuid NOT NULL REFERENCES public.couple_spaces(id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  product_type text NOT NULL,
  principal int NOT NULL,
  interest_rate numeric NOT NULL,
  start_at timestamptz NOT NULL,
  end_at timestamptz NOT NULL,
  status text NOT NULL DEFAULT 'active',
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.point_deposits IS '积分定期存储：status=active 锁定本金，到期 redeem 发利息，提前 redeemed_early 无利息';
COMMENT ON COLUMN public.point_deposits.product_type IS 'quarter|half_year|one_year|two_years';
COMMENT ON COLUMN public.point_deposits.status IS 'active|redeemed|redeemed_early';

ALTER TABLE public.point_deposits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Point deposits: CRUD for own space"
  ON public.point_deposits FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.couple_spaces cs
      WHERE cs.id = point_deposits.couple_space_id
      AND (cs.user_a_id = auth.uid() OR cs.user_b_id = auth.uid())
    )
  );

CREATE INDEX IF NOT EXISTS idx_point_deposits_space_user_status
  ON public.point_deposits (couple_space_id, user_id, status);
