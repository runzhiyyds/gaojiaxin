-- 通过邀请码加入空间：在服务端一次性完成校验与写入，绕过 RLS，避免「已关联过」误报与邀请码查不到
-- 在 Supabase SQL Editor 中执行

create or replace function public.join_by_invite_code(code_input text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  joiner_id uuid;
  code_trimmed text;
  inviter_row record;
  space_id_val uuid;
  space_b_id uuid;
begin
  joiner_id := auth.uid();
  if joiner_id is null then
    return jsonb_build_object('success', false, 'error', 'not_logged_in');
  end if;

  code_trimmed := upper(trim(code_input));
  if length(code_trimmed) <> 6 then
    return jsonb_build_object('success', false, 'error', 'invalid_length');
  end if;

  -- 当前用户是否已关联空间（以服务端为准）
  if exists (
    select 1 from public.profiles
    where id = joiner_id and couple_space_id is not null
  ) then
    return jsonb_build_object('success', false, 'error', 'already_joined');
  end if;

  -- 查邀请码对应的 profile（无 RLS 限制）
  select id, couple_space_id into inviter_row
  from public.profiles
  where invite_code = code_trimmed and couple_space_id is not null
  limit 1;

  if inviter_row.id is null then
    return jsonb_build_object('success', false, 'error', 'invalid_code');
  end if;

  if inviter_row.id = joiner_id then
    return jsonb_build_object('success', false, 'error', 'own_code');
  end if;

  space_id_val := inviter_row.couple_space_id;

  select user_b_id into space_b_id
  from public.couple_spaces
  where id = space_id_val
  limit 1;

  if space_b_id is not null then
    return jsonb_build_object('success', false, 'error', 'space_full');
  end if;

  update public.couple_spaces
  set user_b_id = joiner_id
  where id = space_id_val;

  update public.profiles
  set couple_space_id = space_id_val, updated_at = now()
  where id = joiner_id;

  update public.profiles
  set invite_code = null, updated_at = now()
  where invite_code = code_trimmed;

  return jsonb_build_object('success', true);
end;
$$;

-- 允许已登录用户调用
grant execute on function public.join_by_invite_code(text) to authenticated;
