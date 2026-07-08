-- 在 Supabase SQL Editor 中执行此脚本创建表结构

-- 情侣空间
create table if not exists public.couple_spaces (
  id uuid primary key default gen_random_uuid(),
  user_a_id uuid not null references auth.users(id) on delete cascade,
  user_b_id uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

-- 用户资料（与 auth.users 一对一）
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  nickname text,
  avatar_url text,
  couple_space_id uuid references public.couple_spaces(id) on delete set null,
  invite_code text unique,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 积分项目（预置 + 自定义）
-- 统计周期：与 TAB2 月/年/历史所有对齐；保留 day/week 兼容
create type cycle_type as enum ('day', 'week', 'month', 'year', 'all');

create table if not exists public.point_items (
  id uuid primary key default gen_random_uuid(),
  couple_space_id uuid not null references public.couple_spaces(id) on delete cascade,
  name text not null,
  icon_name text not null default 'star',
  points_per_unit int not null default 1,
  cycle_type cycle_type not null default 'day',
  sort_order int not null default 0,
  is_preset boolean not null default false,
  is_enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 积分记录（edit_used_at 非空表示已使用「一次编辑/删除」机会，不可再改）
create table if not exists public.point_records (
  id uuid primary key default gen_random_uuid(),
  couple_space_id uuid not null references public.couple_spaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  point_item_id uuid not null references public.point_items(id) on delete cascade,
  points int not null,
  record_at timestamptz not null default now(),
  note text,
  created_at timestamptz not null default now(),
  edit_used_at timestamptz
);

-- 商城商品（owner_id：归属用户，即「该用户的积分商城」，对方用积分在此兑换）
create table if not exists public.mall_goods (
  id uuid primary key default gen_random_uuid(),
  couple_space_id uuid not null references public.couple_spaces(id) on delete cascade,
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  description text,
  points_required int not null,
  stock int,
  image_url text,
  sort_order int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- 兑换记录
create table if not exists public.exchange_records (
  id uuid primary key default gen_random_uuid(),
  couple_space_id uuid not null references public.couple_spaces(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  mall_good_id uuid not null references public.mall_goods(id) on delete cascade,
  points_spent int not null,
  created_at timestamptz not null default now()
);

-- RLS
alter table public.couple_spaces enable row level security;
alter table public.profiles enable row level security;
alter table public.point_items enable row level security;
alter table public.point_records enable row level security;
alter table public.mall_goods enable row level security;
alter table public.exchange_records enable row level security;

create policy "Users can read own profile"
  on public.profiles for select using (auth.uid() = id);

create policy "Users can update own profile"
  on public.profiles for update using (auth.uid() = id);

create policy "Users can insert own profile"
  on public.profiles for insert with check (auth.uid() = id);

create policy "Users can read partner profile in same space"
  on public.profiles for select using (
    exists (
      select 1 from public.couple_spaces cs
      where cs.id = profiles.couple_space_id
      and (cs.user_a_id = auth.uid() or cs.user_b_id = auth.uid())
    )
  );

create policy "Spaces: read own"
  on public.couple_spaces for select using (
    user_a_id = auth.uid() or user_b_id = auth.uid()
  );

create policy "Spaces: insert as user_a"
  on public.couple_spaces for insert with check (user_a_id = auth.uid());

create policy "Spaces: update to add user_b"
  on public.couple_spaces for update using (
    user_a_id = auth.uid() or user_b_id = auth.uid()
  );

create policy "Point items: CRUD for own space"
  on public.point_items for all using (
    exists (
      select 1 from public.couple_spaces cs
      where cs.id = point_items.couple_space_id
      and (cs.user_a_id = auth.uid() or cs.user_b_id = auth.uid())
    )
  );

create policy "Point records: CRUD for own space"
  on public.point_records for all using (
    exists (
      select 1 from public.couple_spaces cs
      where cs.id = point_records.couple_space_id
      and (cs.user_a_id = auth.uid() or cs.user_b_id = auth.uid())
    )
  );

create policy "Mall goods: CRUD for own space"
  on public.mall_goods for all using (
    exists (
      select 1 from public.couple_spaces cs
      where cs.id = mall_goods.couple_space_id
      and (cs.user_a_id = auth.uid() or cs.user_b_id = auth.uid())
    )
  );

create policy "Exchange records: CRUD for own space"
  on public.exchange_records for all using (
    exists (
      select 1 from public.couple_spaces cs
      where cs.id = exchange_records.couple_space_id
      and (cs.user_a_id = auth.uid() or cs.user_b_id = auth.uid())
    )
  );

-- 新用户自动创建 profile
create or replace function public.handle_new_user()
returns trigger as $$
begin
  insert into public.profiles (id, nickname)
  values (new.id, coalesce(new.raw_user_meta_data->>'nickname', new.email));
  return new;
end;
$$ language plpgsql security definer;

create or replace trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();
