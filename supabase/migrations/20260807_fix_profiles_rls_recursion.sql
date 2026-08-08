-- Corrige recursão na RLS de profiles e garante leitura do próprio perfil.
-- Não cria nem altera usuários, profiles ou UUIDs.

create or replace function public.current_company_id()
returns uuid
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select p.company_id from public.profiles p where p.id = auth.uid()
$$;

create or replace function public.current_user_is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
set row_security = off
as $$
  select coalesce((select p.role = 'admin' from public.profiles p where p.id = auth.uid()),false)
$$;

revoke all on function public.current_company_id() from public;
revoke all on function public.current_user_is_admin() from public;
grant execute on function public.current_company_id() to authenticated;
grant execute on function public.current_user_is_admin() to authenticated;

drop policy if exists profiles_company on public.profiles;
drop policy if exists profiles_admin_write on public.profiles;
drop policy if exists profiles_self_select on public.profiles;
drop policy if exists profiles_company_select on public.profiles;
drop policy if exists profiles_admin_insert on public.profiles;
drop policy if exists profiles_admin_update on public.profiles;
drop policy if exists profiles_admin_delete on public.profiles;

-- Regra independente e não recursiva: todo usuário lê o próprio profile.
create policy profiles_self_select on public.profiles
for select to authenticated
using (id = auth.uid());

-- Administradores podem consultar os demais perfis apenas da própria empresa.
create policy profiles_company_select on public.profiles
for select to authenticated
using (public.current_user_is_admin() and company_id = public.current_company_id());

create policy profiles_admin_insert on public.profiles
for insert to authenticated
with check (public.current_user_is_admin() and company_id = public.current_company_id());

create policy profiles_admin_update on public.profiles
for update to authenticated
using (public.current_user_is_admin() and company_id = public.current_company_id())
with check (public.current_user_is_admin() and company_id = public.current_company_id());

create policy profiles_admin_delete on public.profiles
for delete to authenticated
using (public.current_user_is_admin() and company_id = public.current_company_id() and id <> auth.uid());

-- Diagnóstico administrativo (SQL Editor):
-- select id,company_id,full_name,role from public.profiles
-- where id='5ffbb956-309d-4eed-b7dc-1da6739ef15d';
