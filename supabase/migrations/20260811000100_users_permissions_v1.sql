-- V1: usuários ativos/inativos e permissões administrativas sem recursão RLS.
alter table public.profiles add column if not exists is_active boolean not null default true;
create index if not exists profiles_company_active_idx on public.profiles(company_id,is_active);

create or replace function public.current_company_id()
returns uuid language sql stable security definer
set search_path=public set row_security=off as $$
  select p.company_id from public.profiles p where p.id=auth.uid() and p.is_active=true
$$;

create or replace function public.current_user_is_admin()
returns boolean language sql stable security definer
set search_path=public set row_security=off as $$
  select coalesce((select p.role='admin' from public.profiles p where p.id=auth.uid() and p.is_active=true),false)
$$;

revoke all on function public.current_company_id() from public;
revoke all on function public.current_user_is_admin() from public;
grant execute on function public.current_company_id() to authenticated;
grant execute on function public.current_user_is_admin() to authenticated;

drop policy if exists profiles_self_select on public.profiles;
drop policy if exists profiles_company_select on public.profiles;
drop policy if exists profiles_admin_insert on public.profiles;
drop policy if exists profiles_admin_update on public.profiles;
drop policy if exists profiles_admin_delete on public.profiles;

create policy profiles_self_select on public.profiles for select to authenticated using(id=auth.uid());
create policy profiles_company_select on public.profiles for select to authenticated
using(public.current_user_is_admin() and company_id=public.current_company_id());
create policy profiles_admin_insert on public.profiles for insert to authenticated
with check(public.current_user_is_admin() and company_id=public.current_company_id());
create policy profiles_admin_update on public.profiles for update to authenticated
using(public.current_user_is_admin() and company_id=public.current_company_id())
with check(public.current_user_is_admin() and company_id=public.current_company_id());

-- Não há exclusão de profiles na V1: preserva toda auditoria histórica.
revoke delete on public.profiles from authenticated;
grant select,insert,update on public.profiles to authenticated;
notify pgrst,'reload schema';
