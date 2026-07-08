-- 收件人（获得心意的一方）对单条 point_records 的一条回应：正文 + 时间
-- 仅能通过 RPC 写入，避免伴侣通过通用 UPDATE 篡改对方回应。

alter table public.point_records
  add column if not exists recipient_comment text;

alter table public.point_records
  add column if not exists recipient_comment_at timestamptz;

create or replace function public.set_point_record_recipient_comment(
  p_record_id uuid,
  p_comment text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_space_id uuid;
begin
  if auth.uid() is null then
    raise exception 'not authenticated';
  end if;

  select pr.user_id, pr.couple_space_id
  into v_user_id, v_space_id
  from public.point_records pr
  where pr.id = p_record_id;

  if v_user_id is null then
    raise exception 'record not found';
  end if;

  if v_user_id <> auth.uid() then
    raise exception 'only the recipient of this record can set recipient comment';
  end if;

  if not exists (
    select 1
    from public.couple_spaces cs
    where cs.id = v_space_id
      and (cs.user_a_id = auth.uid() or cs.user_b_id = auth.uid())
  ) then
    raise exception 'forbidden';
  end if;

  if p_comment is null or length(trim(p_comment)) = 0 then
    update public.point_records
    set
      recipient_comment = null,
      recipient_comment_at = null
    where id = p_record_id;
  else
    update public.point_records
    set
      recipient_comment = trim(p_comment),
      recipient_comment_at = now()
    where id = p_record_id;
  end if;
end;
$$;

grant execute on function public.set_point_record_recipient_comment(uuid, text) to authenticated;
