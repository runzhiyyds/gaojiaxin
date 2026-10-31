-- 关键写入原子化与并发保护：兑换、储值、记录编辑/删除/回应。
-- 依赖现有 couple_spaces、point_records、mall_goods、exchange_records、point_deposits。

CREATE TABLE IF NOT EXISTS public.business_write_requests (
  request_id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  operation text NOT NULL,
  result jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.business_write_requests ENABLE ROW LEVEL SECURITY;

DO $policy$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE schemaname = 'public'
       AND tablename = 'business_write_requests'
       AND policyname = 'Business requests: own rows'
  ) THEN
    CREATE POLICY "Business requests: own rows"
      ON public.business_write_requests FOR ALL
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END
$policy$;

GRANT SELECT, INSERT ON public.business_write_requests TO authenticated;
REVOKE ALL ON public.business_write_requests FROM anon;

CREATE OR REPLACE FUNCTION public.exchange_good_atomic(
  p_couple_space_id uuid,
  p_mall_good_id uuid,
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := auth.uid();
  existing_result jsonb;
  good_row public.mall_goods%ROWTYPE;
  exchange_id uuid;
  earned bigint;
  spent bigint;
  locked bigint;
  available_balance bigint;
  response jsonb;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication required';
  END IF;
  IF NOT EXISTS (
    SELECT 1 FROM public.couple_spaces AS cs
     WHERE cs.id = p_couple_space_id
       AND (cs.user_a_id = current_user_id OR cs.user_b_id = current_user_id)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'couple space is not accessible';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_couple_space_id::text || ':' || current_user_id::text, 0)
  );

  SELECT bwr.result INTO existing_result
    FROM public.business_write_requests AS bwr
   WHERE bwr.request_id = p_request_id
     AND bwr.user_id = current_user_id
     AND bwr.operation = 'exchange';
  IF FOUND THEN RETURN existing_result; END IF;
  IF EXISTS (SELECT 1 FROM public.business_write_requests WHERE request_id = p_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'request id was already used';
  END IF;

  SELECT * INTO good_row
    FROM public.mall_goods AS mg
   WHERE mg.id = p_mall_good_id
     AND mg.couple_space_id = p_couple_space_id
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION '商品不存在'; END IF;
  IF good_row.owner_id = current_user_id THEN RAISE EXCEPTION '不能兑换自己的商品'; END IF;
  IF good_row.stock IS NOT NULL AND good_row.stock < 1 THEN RAISE EXCEPTION '库存不足'; END IF;

  SELECT COALESCE(SUM(pr.points), 0) INTO earned
    FROM public.point_records AS pr
   WHERE pr.couple_space_id = p_couple_space_id AND pr.user_id = current_user_id;
  SELECT COALESCE(SUM(er.points_spent), 0) INTO spent
    FROM public.exchange_records AS er
   WHERE er.couple_space_id = p_couple_space_id AND er.user_id = current_user_id;
  SELECT COALESCE(SUM(pd.principal), 0) INTO locked
    FROM public.point_deposits AS pd
   WHERE pd.couple_space_id = p_couple_space_id
     AND pd.user_id = current_user_id AND pd.status = 'active';
  available_balance := earned - spent - locked;
  IF available_balance < good_row.points_required THEN
    RAISE EXCEPTION '兑换余额不足，当前余额：%', available_balance;
  END IF;

  INSERT INTO public.exchange_records (
    couple_space_id, user_id, mall_good_id, points_spent
  ) VALUES (
    p_couple_space_id, current_user_id, p_mall_good_id, good_row.points_required
  ) RETURNING id INTO exchange_id;

  IF good_row.stock IS NOT NULL THEN
    UPDATE public.mall_goods
       SET stock = good_row.stock - 1, updated_at = now()
     WHERE id = good_row.id;
  END IF;

  response := jsonb_build_object(
    'exchange_record_id', exchange_id,
    'points_spent', good_row.points_required,
    'remaining_balance', available_balance - good_row.points_required
  );
  INSERT INTO public.business_write_requests (request_id, user_id, operation, result)
  VALUES (p_request_id, current_user_id, 'exchange', response);
  RETURN response;
END;
$function$;

CREATE OR REPLACE FUNCTION public.create_point_deposit_atomic(
  p_couple_space_id uuid,
  p_product_type text,
  p_principal integer,
  p_request_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := auth.uid();
  existing_result jsonb;
  earned bigint;
  spent bigint;
  locked bigint;
  available_balance bigint;
  product_rate numeric;
  product_months integer;
  deposit_row public.point_deposits%ROWTYPE;
  response jsonb;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication required';
  END IF;
  IF p_principal < 10 THEN RAISE EXCEPTION '存入心意值至少为 1.0'; END IF;
  CASE p_product_type
    WHEN 'quarter' THEN product_rate := 0.10; product_months := 3;
    WHEN 'half_year' THEN product_rate := 0.15; product_months := 6;
    WHEN 'one_year' THEN product_rate := 0.20; product_months := 12;
    WHEN 'two_years' THEN product_rate := 0.30; product_months := 24;
    ELSE RAISE EXCEPTION '无效的存储产品';
  END CASE;
  IF NOT EXISTS (
    SELECT 1 FROM public.couple_spaces AS cs
     WHERE cs.id = p_couple_space_id
       AND (cs.user_a_id = current_user_id OR cs.user_b_id = current_user_id)
  ) THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'couple space is not accessible';
  END IF;

  PERFORM pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_couple_space_id::text || ':' || current_user_id::text, 0)
  );

  SELECT bwr.result INTO existing_result
    FROM public.business_write_requests AS bwr
   WHERE bwr.request_id = p_request_id
     AND bwr.user_id = current_user_id
     AND bwr.operation = 'deposit';
  IF FOUND THEN RETURN existing_result; END IF;
  IF EXISTS (SELECT 1 FROM public.business_write_requests WHERE request_id = p_request_id) THEN
    RAISE EXCEPTION USING ERRCODE = '23505', MESSAGE = 'request id was already used';
  END IF;

  SELECT COALESCE(SUM(pr.points), 0) INTO earned
    FROM public.point_records AS pr
   WHERE pr.couple_space_id = p_couple_space_id AND pr.user_id = current_user_id;
  SELECT COALESCE(SUM(er.points_spent), 0) INTO spent
    FROM public.exchange_records AS er
   WHERE er.couple_space_id = p_couple_space_id AND er.user_id = current_user_id;
  SELECT COALESCE(SUM(pd.principal), 0) INTO locked
    FROM public.point_deposits AS pd
   WHERE pd.couple_space_id = p_couple_space_id
     AND pd.user_id = current_user_id AND pd.status = 'active';
  available_balance := earned - spent - locked;
  IF available_balance < p_principal THEN
    RAISE EXCEPTION '可用余额不足，当前余额：%', available_balance;
  END IF;

  INSERT INTO public.point_deposits (
    couple_space_id, user_id, product_type, principal, interest_rate,
    start_at, end_at, status
  ) VALUES (
    p_couple_space_id, current_user_id, p_product_type, p_principal, product_rate,
    now(), now() + pg_catalog.make_interval(months => product_months), 'active'
  ) RETURNING * INTO deposit_row;

  response := to_jsonb(deposit_row);
  INSERT INTO public.business_write_requests (request_id, user_id, operation, result)
  VALUES (p_request_id, current_user_id, 'deposit', response);
  RETURN response;
END;
$function$;

ALTER TABLE public.point_records
  ADD COLUMN IF NOT EXISTS row_version bigint NOT NULL DEFAULT 1;

CREATE OR REPLACE FUNCTION public.bump_point_record_version()
RETURNS trigger
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
BEGIN
  NEW.row_version := OLD.row_version + 1;
  RETURN NEW;
END;
$function$;

DO $trigger$
BEGIN
  IF NOT EXISTS (
    SELECT 1
      FROM pg_trigger
     WHERE tgname = 'bump_point_record_version_trigger'
       AND tgrelid = 'public.point_records'::regclass
       AND NOT tgisinternal
  ) THEN
    CREATE TRIGGER bump_point_record_version_trigger
      BEFORE UPDATE ON public.point_records
      FOR EACH ROW EXECUTE FUNCTION public.bump_point_record_version();
  END IF;
END
$trigger$;

CREATE OR REPLACE FUNCTION public.update_point_record_once_if_version(
  p_record_id uuid,
  p_expected_version bigint,
  p_point_item_id uuid,
  p_note text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := auth.uid();
  changed public.point_records%ROWTYPE;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication required';
  END IF;
  UPDATE public.point_records AS pr
     SET point_item_id = p_point_item_id,
         note = NULLIF(trim(p_note), ''),
         edit_used_at = now()
   WHERE pr.id = p_record_id
     AND pr.row_version = p_expected_version
     AND pr.edit_used_at IS NULL
     AND pr.user_id <> current_user_id
     AND EXISTS (
       SELECT 1 FROM public.point_items AS pi
        WHERE pi.id = p_point_item_id
          AND pi.couple_space_id = pr.couple_space_id
          AND pi.is_enabled = true
     )
  RETURNING pr.* INTO changed;
  IF NOT FOUND THEN RAISE EXCEPTION '记录已变化，请刷新后重试'; END IF;
  RETURN to_jsonb(changed);
END;
$function$;

CREATE OR REPLACE FUNCTION public.delete_point_record_if_version(
  p_record_id uuid,
  p_expected_version bigint
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := auth.uid();
  deleted public.point_records%ROWTYPE;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication required';
  END IF;
  DELETE FROM public.point_records AS pr
   WHERE pr.id = p_record_id
     AND pr.row_version = p_expected_version
     AND pr.user_id <> current_user_id
  RETURNING pr.* INTO deleted;
  IF NOT FOUND THEN RAISE EXCEPTION '记录已变化，请刷新后重试'; END IF;
  RETURN to_jsonb(deleted);
END;
$function$;

CREATE OR REPLACE FUNCTION public.set_point_record_comment_if_version(
  p_record_id uuid,
  p_expected_version bigint,
  p_comment text
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = ''
AS $function$
DECLARE
  current_user_id uuid := auth.uid();
  changed public.point_records%ROWTYPE;
BEGIN
  IF current_user_id IS NULL THEN
    RAISE EXCEPTION USING ERRCODE = '42501', MESSAGE = 'authentication required';
  END IF;
  UPDATE public.point_records AS pr
     SET recipient_comment = NULLIF(trim(p_comment), ''),
         recipient_comment_at = CASE
           WHEN NULLIF(trim(p_comment), '') IS NULL THEN NULL ELSE now()
         END
   WHERE pr.id = p_record_id
     AND pr.row_version = p_expected_version
     AND pr.user_id = current_user_id
  RETURNING pr.* INTO changed;
  IF NOT FOUND THEN RAISE EXCEPTION '记录已变化，请刷新后重试'; END IF;
  RETURN to_jsonb(changed);
END;
$function$;

REVOKE ALL ON FUNCTION public.exchange_good_atomic(uuid, uuid, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.create_point_deposit_atomic(uuid, text, integer, uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.update_point_record_once_if_version(uuid, bigint, uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.delete_point_record_if_version(uuid, bigint) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.set_point_record_comment_if_version(uuid, bigint, text) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.exchange_good_atomic(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_point_deposit_atomic(uuid, text, integer, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_point_record_once_if_version(uuid, bigint, uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_point_record_if_version(uuid, bigint) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_point_record_comment_if_version(uuid, bigint, text) TO authenticated;
