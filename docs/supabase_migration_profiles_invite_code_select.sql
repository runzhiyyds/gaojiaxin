-- 修复：输入邀请码加入时，当前用户（尚未在空间内）无法读取创建者的 profile，导致“邀请码无效”
-- 允许已登录用户通过 invite_code 查询到对应 profile（仅用于获取 couple_space_id 以加入空间）
-- 在 Supabase SQL Editor 中执行

create policy "Users can read profile by invite code for join"
  on public.profiles for select
  using (
    auth.uid() is not null
    and invite_code is not null
    and invite_code != ''
  );
