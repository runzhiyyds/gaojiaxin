-- 推送相关表结构与触发函数（示例），请在 Supabase Dashboard 中执行或放入 migrations。

-- 设备表：一条记录代表某个用户在某个情侣空间下的一台设备
create table if not exists public.push_devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users (id) on delete cascade,
  couple_space_id uuid not null references public.couple_spaces (id) on delete cascade,
  device_token text not null,
  platform text not null check (platform in ('android', 'ios', 'other')),
  app_version text not null default '',
  is_active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists push_devices_user_space_token_idx
  on public.push_devices (user_id, couple_space_id, device_token);

alter table public.push_devices
  enable row level security;

create policy "user can manage own devices"
on public.push_devices
for all
using (auth.uid() = user_id)
with check (auth.uid() = user_id);


-- 推送日志表：方便排查失败原因，可按需裁剪
create table if not exists public.push_logs (
  id bigserial primary key,
  user_id uuid not null,
  couple_space_id uuid,
  device_token text,
  event_type text not null, -- points_added / redeem_success 等
  payload jsonb not null,
  success boolean not null,
  error_message text,
  created_at timestamptz not null default now()
);

alter table public.push_logs
  enable row level security;

create policy "user can view own push logs"
on public.push_logs
for select
using (auth.uid() = user_id);


-- Edge Function 触发：积分新增 -> on_points_added
-- 仅当存在 net schema（已启用 pg_net）时用动态 SQL 调用，否则跳过，保证 INSERT 一定成功
create or replace function public.handle_points_added()
returns trigger
language plpgsql
as $$
declare
  target_user uuid;
  req_url text := 'https://<your-project-ref>.functions.supabase.co/on_points_added';
  req_headers jsonb := jsonb_build_object('Content-Type', 'application/json');
  req_body jsonb;
begin
  target_user := new.user_id;
  if not exists (select 1 from pg_catalog.pg_namespace where nspname = 'net') then
    return new;
  end if;
  req_body := jsonb_build_object(
    'record_id', new.id,
    'couple_space_id', new.couple_space_id,
    'to_user_id', target_user,
    'points', new.points,
    'note', new.note
  );
  execute 'select net.http_post($1, $2, $3, $4)'
    using req_url, req_body, '{}'::jsonb, req_headers;
  return new;
exception
  when others then
    return new; -- 推送失败也不影响插入
end;
$$;

drop trigger if exists on_points_added_trigger on public.point_records;
create trigger on_points_added_trigger
after insert on public.point_records
for each row
execute procedure public.handle_points_added();


-- Edge Function 触发：兑换成功 -> on_redeem_success
-- 仅当存在 net schema（已启用 pg_net）时用动态 SQL 调用，否则跳过，保证 INSERT 一定成功
create or replace function public.handle_redeem_success()
returns trigger
language plpgsql
as $$
declare
  owner_id uuid;
  good_name text;
  req_url text := 'https://<your-project-ref>.functions.supabase.co/on_redeem_success';
  req_headers jsonb := jsonb_build_object('Content-Type', 'application/json');
  req_body jsonb;
begin
  if not exists (select 1 from pg_catalog.pg_namespace where nspname = 'net') then
    return new;
  end if;
  select mg.owner_id, mg.name into owner_id, good_name
  from public.mall_goods mg
  where mg.id = new.mall_good_id;

  req_body := jsonb_build_object(
    'exchange_id', new.id,
    'couple_space_id', new.couple_space_id,
    'from_user_id', new.user_id,
    'to_user_id', owner_id,
    'good_name', good_name,
    'points_spent', new.points_spent
  );
  execute 'select net.http_post($1, $2, $3, $4)'
    using req_url, req_body, '{}'::jsonb, req_headers;
  return new;
exception
  when others then
    return new; -- 推送失败也不影响插入
end;
$$;

drop trigger if exists on_redeem_success_trigger on public.exchange_records;
create trigger on_redeem_success_trigger
after insert on public.exchange_records
for each row
execute procedure public.handle_redeem_success();

