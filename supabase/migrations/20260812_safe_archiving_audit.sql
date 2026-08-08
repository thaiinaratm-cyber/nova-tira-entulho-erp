-- Arquivamento seguro e auditoria operacional da V1. Nenhum dado atual é removido.
alter table public.clients add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.clients add column if not exists updated_by uuid references public.profiles(id) on delete set null;
alter table public.clients add column if not exists archived_at timestamptz;
alter table public.clients add column if not exists archived_by uuid references public.profiles(id) on delete set null;
alter table public.client_addresses add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.client_addresses add column if not exists updated_by uuid references public.profiles(id) on delete set null;
alter table public.client_addresses add column if not exists updated_at timestamptz not null default now();
alter table public.services add column if not exists created_by uuid references public.profiles(id) on delete set null;
alter table public.services add column if not exists updated_by uuid references public.profiles(id) on delete set null;

create index if not exists clients_company_active_idx on public.clients(company_id,name) where archived_at is null;
create index if not exists clients_company_archived_idx on public.clients(company_id,archived_at desc) where archived_at is not null;

create table if not exists public.client_archive_events(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id),
 client_id uuid not null references public.clients(id),
 action text not null check(action in ('archived','restored')),
 performed_by uuid references public.profiles(id) on delete set null,
 occurred_at timestamptz not null default now()
);
create index if not exists client_archive_events_company_time_idx on public.client_archive_events(company_id,occurred_at desc);
create index if not exists client_archive_events_client_idx on public.client_archive_events(client_id,occurred_at desc);
alter table public.client_archive_events enable row level security;

drop policy if exists client_archive_events_admin_select on public.client_archive_events;
create policy client_archive_events_admin_select on public.client_archive_events for select to authenticated
using(public.current_user_is_admin() and company_id=public.current_company_id());
revoke all on public.client_archive_events from authenticated;
grant select on public.client_archive_events to authenticated;

create or replace function public.audit_client_changes()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
begin
 if tg_op='INSERT' then
  new.created_by=coalesce(new.created_by,auth.uid());new.updated_by=coalesce(new.updated_by,auth.uid());new.updated_at=coalesce(new.updated_at,now());
  return new;
 end if;
 new.updated_by=auth.uid();new.updated_at=now();
 if old.archived_at is distinct from new.archived_at then
  if not public.current_user_is_admin() then raise exception 'Somente administradores podem arquivar ou restaurar clientes';end if;
  if new.archived_at is null then new.archived_by=null;else new.archived_by=auth.uid();end if;
 end if;
 return new;
end $$;

drop trigger if exists clients_audit_changes on public.clients;
create trigger clients_audit_changes before insert or update on public.clients for each row execute function public.audit_client_changes();

create or replace function public.record_client_archive_event()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
begin
 if old.archived_at is distinct from new.archived_at then
  insert into public.client_archive_events(company_id,client_id,action,performed_by,occurred_at)
  values(new.company_id,new.id,case when new.archived_at is null then 'restored' else 'archived' end,auth.uid(),now());
 end if;
 return new;
end $$;

drop trigger if exists clients_record_archive_event on public.clients;
create trigger clients_record_archive_event after update on public.clients for each row execute function public.record_client_archive_event();

create or replace function public.audit_operational_actor()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
begin
 if tg_op='INSERT' then new.created_by=coalesce(new.created_by,auth.uid());end if;
 new.updated_by=auth.uid();new.updated_at=now();return new;
end $$;

drop trigger if exists client_addresses_audit_actor on public.client_addresses;
create trigger client_addresses_audit_actor before insert or update on public.client_addresses for each row execute function public.audit_operational_actor();
drop trigger if exists services_audit_actor on public.services;
create trigger services_audit_actor before insert or update on public.services for each row execute function public.audit_operational_actor();

create or replace function public.archive_client(client_id uuid)
returns public.clients language plpgsql security definer set search_path=public set row_security=off as $$
declare result public.clients;
begin
 if not public.current_user_is_admin() then raise exception 'Somente administradores podem arquivar clientes';end if;
 update public.clients set archived_at=coalesce(archived_at,now()) where id=client_id and company_id=public.current_company_id() returning * into result;
 if result.id is null then raise exception 'Cliente não encontrado na empresa atual';end if;
 return result;
end $$;

create or replace function public.restore_client(client_id uuid)
returns public.clients language plpgsql security definer set search_path=public set row_security=off as $$
declare result public.clients;
begin
 if not public.current_user_is_admin() then raise exception 'Somente administradores podem restaurar clientes';end if;
 update public.clients set archived_at=null where id=client_id and company_id=public.current_company_id() and archived_at is not null returning * into result;
 if result.id is null then raise exception 'Cliente arquivado não encontrado na empresa atual';end if;
 return result;
end $$;

revoke all on function public.archive_client(uuid) from public;
revoke all on function public.restore_client(uuid) from public;
grant execute on function public.archive_client(uuid) to authenticated;
grant execute on function public.restore_client(uuid) to authenticated;

-- Operadores autenticados nunca removem fisicamente registros operacionais.
drop policy if exists clients_company_delete on public.clients;
drop policy if exists service_payments_delete on public.service_payments;
drop policy if exists service_payments_update on public.service_payments;
revoke delete on public.clients from authenticated;
revoke delete on public.client_addresses from authenticated;
revoke delete on public.services from authenticated;
revoke delete on public.service_payments from authenticated;
revoke update on public.service_payments from authenticated;
revoke delete on public.receipts from authenticated;

notify pgrst,'reload schema';
