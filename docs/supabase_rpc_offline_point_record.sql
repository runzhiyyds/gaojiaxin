-- 「记一笔」离线发件箱的幂等事务 RPC。
-- 执行前要求：已执行 supabase_rpc_atomic_writes.sql，且已备份数据库。
-- 设计边界：仅新建记录，不覆盖任何已有数据；相同 request_id 永远只生效一次。

CREATE OR REPLACE FUNCTION public.create_point_record_offline_atomic(
  p_couple_space_id uuid,
  p_partner_user_id uuid,
  p_point_item_id uuid,
  p_points integer,
  p_record_at timestamptz,
  p_note text,
  p_love_dimension text,
  p_is_domineering boolean,
  p_random_bonus integer,
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := auth.uid();
  space_row public.couple_spaces%ROWTYPE;
  item_row public.point_items%ROWTYPE;
  existing_result jsonb;
  main_record_id uuid;
  bonus_record_id uuid;
  bonus_item_id uuid;
  default_product text;
  deposit_rate numeric;
  deposit_months integer;
  active_deposit_id uuid;
  response jsonb;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication required';
  END IF;
  IF p_points < 1 OR p_points > 9999 THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = '心意值超出允许范围';
  END IF;
  IF p_is_domineering IS NULL OR p_random_bonus IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = '记录模式不完整';
  END IF;
  IF p_record_at IS NULL OR p_record_at < now() - interval '3 years'
      OR p_record_at > now() + interval '1 year' THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = '记录时间超出允许范围';
  END IF;
  IF p_love_dimension IS NOT NULL AND p_love_dimension NOT IN (
    'care', 'companionship', 'understanding', 'growth',
    'responsibility', 'ritual', 'passion'
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = '无效的心意维度';
  END IF;
  IF NOT p_is_domineering
      AND (p_random_bonus < GREATEST(1, floor(p_points * 0.5)::integer)
           OR p_random_bonus > p_points * 10) THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = '随机回馈超出允许范围';
  END IF;

  SELECT * INTO space_row
    FROM public.couple_spaces AS cs
   WHERE cs.id = p_couple_space_id
     AND (cs.user_a_id = current_user_id OR cs.user_b_id = current_user_id);
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'couple space is not accessible';
  END IF;
  IF p_partner_user_id = current_user_id OR
     p_partner_user_id <> CASE
       WHEN space_row.user_a_id = current_user_id THEN space_row.user_b_id
       ELSE space_row.user_a_id
     END THEN
    RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = '对方账号已变化';
  END IF;

  -- 同一情侣空间的离线记录串行化，避免并发创建多个随机奖励项。
  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_couple_space_id::text || ':offline-record', 0)
  );

  SELECT bwr.result INTO existing_result
    FROM public.business_write_requests AS bwr
   WHERE bwr.request_id = p_request_id
     AND bwr.user_id = current_user_id
     AND bwr.operation = 'record_point';
  IF FOUND THEN RETURN existing_result; END IF;
  IF EXISTS (SELECT 1 FROM public.business_write_requests WHERE request_id = p_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'request id was already used';
  END IF;

  SELECT * INTO item_row
    FROM public.point_items AS pi
   WHERE pi.id = p_point_item_id
     AND pi.couple_space_id = p_couple_space_id
     AND pi.is_enabled = true
     AND pi.name <> '随机奖励';
  IF NOT FOUND THEN
    RAISE EXCEPTION USING ERRCODE = '23503', MESSAGE = '心意项目已删除或停用';
  END IF;

  INSERT INTO public.point_records (
    couple_space_id, user_id, point_item_id, points, record_at, note, love_dimension
  ) VALUES (
    p_couple_space_id, p_partner_user_id, p_point_item_id, p_points, p_record_at,
    NULLIF(trim(p_note), ''),
    CASE WHEN p_love_dimension IS NULL THEN NULL
         ELSE p_love_dimension::public.love_dimension END
  ) RETURNING id INTO main_record_id;

  IF NOT p_is_domineering THEN
    SELECT pi.id INTO bonus_item_id
      FROM public.point_items AS pi
     WHERE pi.couple_space_id = p_couple_space_id AND pi.name = '随机奖励'
     ORDER BY pi.created_at
     LIMIT 1;
    IF bonus_item_id IS NULL THEN
      INSERT INTO public.point_items (
        couple_space_id, name, icon_name, points_per_unit, cycle_type,
        sort_order, is_preset, is_enabled, is_default
      ) VALUES (
        p_couple_space_id, '随机奖励', 'auto_awesome', 1, 'month',
        9999, false, true, false
      ) RETURNING id INTO bonus_item_id;
    END IF;
    INSERT INTO public.point_records (
      couple_space_id, user_id, point_item_id, points, record_at, note
    ) VALUES (
      p_couple_space_id, current_user_id, bonus_item_id, p_random_bonus, p_record_at,
      item_row.name || CASE WHEN NULLIF(trim(p_note), '') IS NULL
        THEN '' ELSE '：' || trim(p_note) END
    ) RETURNING id INTO bonus_record_id;
  END IF;

  -- 保留原有「新奖励自动存入对方默认定期」语义，并纳入同一事务。
  SELECT udd.product_type INTO default_product
    FROM public.user_deposit_defaults AS udd
   WHERE udd.user_id = p_partner_user_id
     AND udd.couple_space_id = p_couple_space_id;
  IF default_product IS NOT NULL THEN
    CASE default_product
      WHEN 'quarter' THEN deposit_rate := 0.10; deposit_months := 3;
      WHEN 'half_year' THEN deposit_rate := 0.15; deposit_months := 6;
      WHEN 'one_year' THEN deposit_rate := 0.20; deposit_months := 12;
      WHEN 'two_years' THEN deposit_rate := 0.30; deposit_months := 24;
      ELSE RAISE EXCEPTION USING ERRCODE = '23514', MESSAGE = '默认存储产品无效';
    END CASE;
    SELECT pd.id INTO active_deposit_id
      FROM public.point_deposits AS pd
     WHERE pd.couple_space_id = p_couple_space_id
       AND pd.user_id = p_partner_user_id
       AND pd.product_type = default_product
       AND pd.status = 'active'
     ORDER BY pd.created_at DESC
     LIMIT 1
     FOR UPDATE;
    IF active_deposit_id IS NULL THEN
      INSERT INTO public.point_deposits (
        couple_space_id, user_id, product_type, principal, interest_rate,
        start_at, end_at, status
      ) VALUES (
        p_couple_space_id, p_partner_user_id, default_product, p_points, deposit_rate,
        now(), now() + pg_catalog.make_interval(months => deposit_months), 'active'
      );
    ELSE
      UPDATE public.point_deposits
         SET principal = principal + p_points
       WHERE id = active_deposit_id;
    END IF;
  END IF;

  response := jsonb_build_object(
    'record_id', main_record_id,
    'bonus_record_id', bonus_record_id,
    'bonus', CASE WHEN p_is_domineering THEN 0 ELSE p_random_bonus END,
    'auto_deposit', default_product IS NOT NULL
  );
  INSERT INTO public.business_write_requests (request_id, user_id, operation, result)
  VALUES (p_request_id, current_user_id, 'record_point', response);
  RETURN response;
END;
$function$;

REVOKE ALL ON FUNCTION public.create_point_record_offline_atomic(
  uuid, uuid, uuid, integer, timestamptz, text, text, boolean, integer, uuid
) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.create_point_record_offline_atomic(
  uuid, uuid, uuid, integer, timestamptz, text, text, boolean, integer, uuid
) TO authenticated;
