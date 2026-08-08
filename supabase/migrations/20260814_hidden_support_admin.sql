-- Administrador técnico oculto. Todos os profiles atuais permanecem com is_support=false.
alter table public.profiles add column if not exists is_support boolean not null default false;
create index if not exists profiles_company_visible_idx on public.profiles(company_id,created_at) where is_support=false;

create or replace function public.current_user_is_support()
returns boolean language sql stable security definer
set search_path=public set row_security=off as $$
 select coalesce((select p.is_support and p.role='admin' and p.is_active from public.profiles p where p.id=auth.uid()),false)
$$;
revoke all on function public.current_user_is_support() from public;
grant execute on function public.current_user_is_support() to authenticated;

drop policy if exists profiles_self_select on public.profiles;
drop policy if exists profiles_company_select on public.profiles;
drop policy if exists profiles_admin_insert on public.profiles;
drop policy if exists profiles_admin_update on public.profiles;

create policy profiles_self_select on public.profiles for select to authenticated using(id=auth.uid());
create policy profiles_company_select on public.profiles for select to authenticated
using(public.current_user_is_admin() and company_id=public.current_company_id() and (is_support=false or public.current_user_is_support()));
create policy profiles_admin_insert on public.profiles for insert to authenticated
with check(public.current_user_is_admin() and company_id=public.current_company_id() and is_support=false);
create policy profiles_admin_update on public.profiles for update to authenticated
using(public.current_user_is_admin() and company_id=public.current_company_id() and is_support=false)
with check(public.current_user_is_admin() and company_id=public.current_company_id() and is_support=false);

-- O frontend autenticado não recebe privilégio para gravar is_support.
revoke insert,update on public.profiles from authenticated;
grant insert(id,company_id,full_name,role,is_active,created_at,updated_at) on public.profiles to authenticated;
grant update(full_name,role,is_active,updated_at) on public.profiles to authenticated;

create or replace function public.protect_support_profile()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
begin
 if auth.uid() is not null then
  if tg_op='DELETE' and old.is_support then raise exception 'Profile de suporte não pode ser excluído';end if;
  if tg_op='UPDATE' and (old.is_support or new.is_support is distinct from old.is_support) then raise exception 'Profile de suporte só pode ser configurado diretamente no banco';end if;
 end if;
 return case when tg_op='DELETE' then old else new end;
end $$;
drop trigger if exists profiles_protect_support on public.profiles;
create trigger profiles_protect_support before update or delete on public.profiles for each row execute function public.protect_support_profile();

-- Snapshot de autoria: mantém o responsável visível em históricos sem expor seu profile administrativo.
alter table public.service_payments add column if not exists created_by_name text;
update public.service_payments payment set created_by_name=profile.full_name
from public.profiles profile where payment.created_by=profile.id and payment.created_by_name is null;

create or replace function public.guard_service_payment()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
declare service_company uuid;service_amount numeric(12,2);already_received numeric(12,2);
begin
 select company_id,amount into service_company,service_amount from public.services where id=new.service_id for update;
 if service_company is null then raise exception 'Ordem de serviço não encontrada';end if;
 if new.company_id<>service_company then raise exception 'Empresa do pagamento não corresponde à OS';end if;
 select coalesce(sum(amount),0) into already_received from public.service_payments where service_id=new.service_id and id<>new.id;
 if already_received+new.amount>service_amount then raise exception 'Pagamento superior ao saldo restante';end if;
 if new.created_by is null then new.created_by=auth.uid();end if;
 if new.created_by_name is null then select full_name into new.created_by_name from public.profiles where id=new.created_by;end if;
 return new;
end $$;

alter table public.service_events add column if not exists performed_by_name text;
alter table public.client_archive_events add column if not exists performed_by_name text;
update public.service_events event set performed_by_name=profile.full_name from public.profiles profile where event.performed_by=profile.id and event.performed_by_name is null;
update public.client_archive_events event set performed_by_name=profile.full_name from public.profiles profile where event.performed_by=profile.id and event.performed_by_name is null;

create or replace function public.snapshot_audit_actor_name()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
begin
 if new.performed_by_name is null then select full_name into new.performed_by_name from public.profiles where id=new.performed_by;end if;
 return new;
end $$;
drop trigger if exists service_events_actor_snapshot on public.service_events;
create trigger service_events_actor_snapshot before insert on public.service_events for each row execute function public.snapshot_audit_actor_name();
drop trigger if exists client_archive_events_actor_snapshot on public.client_archive_events;
create trigger client_archive_events_actor_snapshot before insert on public.client_archive_events for each row execute function public.snapshot_audit_actor_name();

notify pgrst,'reload schema';
