-- 心意首页聚合读取：把原先 8 次公网请求合并为 1 次 RPC。
-- 执行位置：Supabase Dashboard -> SQL Editor。
-- 安全边界：只允许已登录用户读取自己所在的情侣空间；不使用 SECURITY DEFINER 绕过 RLS。

CREATE OR REPLACE FUNCTION public.get_points_home_snapshot(
  p_couple_space_id uuid,
  p_record_limit integer DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := auth.uid();
  partner_user_id uuid;
  safe_record_limit integer := GREATEST(1, LEAST(COALESCE(p_record_limit, 200), 500));
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'authentication required';
  END IF;

  SELECT CASE
           WHEN cs.user_a_id = current_user_id THEN cs.user_b_id
           ELSE cs.user_a_id
         END
    INTO partner_user_id
    FROM public.couple_spaces AS cs
   WHERE cs.id = p_couple_space_id
     AND (cs.user_a_id = current_user_id OR cs.user_b_id = current_user_id);

  IF NOT FOUND THEN
    RAISE EXCEPTION USING
      ERRCODE = '42501',
      MESSAGE = 'couple space is not accessible';
  END IF;

  RETURN jsonb_build_object(
    'couple_space_id', p_couple_space_id,
    'current_user_id', current_user_id,
    'partner_user_id', partner_user_id,
    'items', COALESCE((
      SELECT jsonb_agg(to_jsonb(item_row) ORDER BY item_row.sort_order, item_row.id)
        FROM public.point_items AS item_row
       WHERE item_row.couple_space_id = p_couple_space_id
         AND item_row.is_enabled = true
    ), '[]'::jsonb),
    'records', COALESCE((
      SELECT jsonb_agg(
               to_jsonb(record_row)
               ORDER BY record_row.record_at DESC, record_row.id DESC
             )
        FROM (
          SELECT pr.*
            FROM public.point_records AS pr
           WHERE pr.couple_space_id = p_couple_space_id
           ORDER BY pr.record_at DESC, pr.id DESC
           LIMIT safe_record_limit
        ) AS record_row
    ), '[]'::jsonb),
    'my_total_earned', COALESCE((
      SELECT SUM(pr.points)
        FROM public.point_records AS pr
       WHERE pr.couple_space_id = p_couple_space_id
         AND pr.user_id = current_user_id
    ), 0),
    'partner_total_earned', COALESCE((
      SELECT SUM(pr.points)
        FROM public.point_records AS pr
       WHERE pr.couple_space_id = p_couple_space_id
         AND pr.user_id = partner_user_id
    ), 0),
    'my_total_spent', COALESCE((
      SELECT SUM(er.points_spent)
        FROM public.exchange_records AS er
       WHERE er.couple_space_id = p_couple_space_id
         AND er.user_id = current_user_id
    ), 0),
    'partner_total_spent', COALESCE((
      SELECT SUM(er.points_spent)
        FROM public.exchange_records AS er
       WHERE er.couple_space_id = p_couple_space_id
         AND er.user_id = partner_user_id
    ), 0),
    'my_locked', COALESCE((
      SELECT SUM(pd.principal)
        FROM public.point_deposits AS pd
       WHERE pd.couple_space_id = p_couple_space_id
         AND pd.user_id = current_user_id
         AND pd.status = 'active'
    ), 0),
    'partner_locked', COALESCE((
      SELECT SUM(pd.principal)
        FROM public.point_deposits AS pd
       WHERE pd.couple_space_id = p_couple_space_id
         AND pd.user_id = partner_user_id
         AND pd.status = 'active'
    ), 0),
    'generated_at', now()
  );
END;
$function$;

REVOKE ALL ON FUNCTION public.get_points_home_snapshot(uuid, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_points_home_snapshot(uuid, integer) FROM anon;
GRANT EXECUTE ON FUNCTION public.get_points_home_snapshot(uuid, integer) TO authenticated;

-- 支撑首页最近记录和累计值；IF NOT EXISTS 可安全重复执行。
CREATE INDEX IF NOT EXISTS idx_point_records_space_record_at
  ON public.point_records (couple_space_id, record_at DESC, id DESC);

CREATE INDEX IF NOT EXISTS idx_point_records_space_user
  ON public.point_records (couple_space_id, user_id);

CREATE INDEX IF NOT EXISTS idx_exchange_records_space_user
  ON public.exchange_records (couple_space_id, user_id);

-- 执行后可用以下只读语句确认函数已注册：
-- SELECT p.proname, p.prosecdef
-- FROM pg_proc AS p
-- JOIN pg_namespace AS n ON n.oid = p.pronamespace
-- WHERE n.nspname = 'public' AND p.proname = 'get_points_home_snapshot';
-- 预期：proname 为 get_points_home_snapshot，prosecdef 为 false（即 SECURITY INVOKER）。
