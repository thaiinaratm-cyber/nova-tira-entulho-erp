-- Sprint 2: agenda, capacidade futura e auditoria operacional.

create table if not exists public.service_events(
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  service_id uuid not null references public.services(id) on delete cascade,
  event_type text not null check(event_type in ('delivery_confirmed','collection_requested','collection_confirmed','service_cancelled')),
  previous_status public.service_status,
  new_status public.service_status not null,
  performed_by uuid references public.profiles(id) on delete set null,
  occurred_at timestamptz not null default now(),
  notes text
);
create index if not exists service_events_service_time_idx on public.service_events(service_id,occurred_at desc);
create index if not exists service_events_company_time_idx on public.service_events(company_id,occurred_at desc);
alter table public.service_events enable row level security;
drop policy if exists service_events_company_select on public.service_events;
create policy service_events_company_select on public.service_events for select to authenticated using(company_id=public.current_company_id());
grant select on public.service_events to authenticated;

create or replace function public.projected_dumpster_availability(target_date date, exclude_service_id uuid default null)
returns integer
language sql
stable
security definer
set search_path=public
set row_security=off
as $$
  with company as(select public.current_company_id() id),
  capacity as(
    select coalesce((s.value#>>'{}')::integer,0) total
    from public.settings s,company c
    where s.company_id=c.id and s.key='total_dumpsters'
  ), commitments as(
    select coalesce(sum(s.quantity),0)::integer used
    from public.services s,company c
    where s.company_id=c.id
      and (exclude_service_id is null or s.id<>exclude_service_id)
      and (
        (s.status in ('delivered','waiting_collection') and coalesce(s.deadline_date,target_date)>target_date)
        or
        (s.status='scheduled'
          and s.scheduled_delivery_date<=target_date
          and (s.scheduled_delivery_date+7)>target_date)
      )
  )
  select greatest(0,coalesce(capacity.total,0)-commitments.used) from capacity cross join commitments
$$;
grant execute on function public.projected_dumpster_availability(date,uuid) to authenticated;

create or replace function public.prevent_negative_inventory()
returns trigger
language plpgsql
security definer
set search_path=public
set row_security=off
as $$
declare available integer;total integer;used integer;
begin
  if new.status='scheduled' then
    select public.projected_dumpster_availability(new.scheduled_delivery_date,new.id) into available;
    if new.quantity>coalesce(available,0) then
      raise exception 'Capacidade insuficiente para %: % caçambas solicitadas, % projetadas como disponíveis',new.scheduled_delivery_date,new.quantity,coalesce(available,0);
    end if;
  elsif new.status in ('delivered','waiting_collection') then
    select coalesce((value#>>'{}')::integer,0) into total from public.settings where company_id=new.company_id and key='total_dumpsters';
    select coalesce(sum(quantity),0) into used from public.services where company_id=new.company_id and status in ('delivered','waiting_collection') and id<>new.id;
    if used+new.quantity>coalesce(total,0) then raise exception 'Quantidade de caçambas indisponível';end if;
  end if;
  return new;
end$$;

create or replace function public.confirm_delivery(service_id uuid)
returns public.services language plpgsql security definer set search_path=public set row_security=off as $$
declare result public.services;company uuid:=public.current_company_id();
begin
  update public.services set delivered_at=now(),deadline_date=(now()+interval '7 days')::date,status='delivered'
  where id=service_id and company_id=company and status='scheduled' returning * into result;
  if result.id is null then raise exception 'Serviço inválido, de outra empresa ou não está agendado';end if;
  insert into public.service_events(company_id,service_id,event_type,previous_status,new_status,performed_by)
  values(company,result.id,'delivery_confirmed','scheduled','delivered',auth.uid());
  return result;
end$$;

create or replace function public.request_collection(service_id uuid)
returns public.services language plpgsql security definer set search_path=public set row_security=off as $$
declare result public.services;company uuid:=public.current_company_id();
begin
  update public.services set status='waiting_collection' where id=service_id and company_id=company and status='delivered' returning * into result;
  if result.id is null then raise exception 'Serviço inválido, de outra empresa ou não está entregue';end if;
  insert into public.service_events(company_id,service_id,event_type,previous_status,new_status,performed_by)
  values(company,result.id,'collection_requested','delivered','waiting_collection',auth.uid());
  return result;
end$$;

create or replace function public.confirm_collection(service_id uuid)
returns public.services language plpgsql security definer set search_path=public set row_security=off as $$
declare result public.services;company uuid:=public.current_company_id();
begin
  update public.services set collected_at=now(),status='completed'
  where id=service_id and company_id=company and status='waiting_collection' returning * into result;
  if result.id is null then raise exception 'Serviço inválido, de outra empresa ou não está aguardando retirada';end if;
  insert into public.service_events(company_id,service_id,event_type,previous_status,new_status,performed_by)
  values(company,result.id,'collection_confirmed','waiting_collection','completed',auth.uid());
  return result;
end$$;

create or replace function public.cancel_scheduled_service(service_id uuid)
returns public.services language plpgsql security definer set search_path=public set row_security=off as $$
declare result public.services;company uuid:=public.current_company_id();received numeric(12,2);
begin
  select coalesce(sum(amount),0) into received from public.service_payments where service_payments.service_id=$1;
  if received>0 then raise exception 'A OS possui pagamento registrado e não pode ser cancelada sem tratamento financeiro';end if;
  update public.services set status='cancelled' where id=service_id and company_id=company and status='scheduled' returning * into result;
  if result.id is null then raise exception 'Serviço inválido, de outra empresa ou não está agendado';end if;
  insert into public.service_events(company_id,service_id,event_type,previous_status,new_status,performed_by)
  values(company,result.id,'service_cancelled','scheduled','cancelled',auth.uid());
  return result;
end$$;

revoke all on function public.confirm_delivery(uuid) from public;
revoke all on function public.request_collection(uuid) from public;
revoke all on function public.confirm_collection(uuid) from public;
revoke all on function public.cancel_scheduled_service(uuid) from public;
grant execute on function public.confirm_delivery(uuid) to authenticated;
grant execute on function public.request_collection(uuid) to authenticated;
grant execute on function public.confirm_collection(uuid) to authenticated;
grant execute on function public.cancel_scheduled_service(uuid) to authenticated;

create or replace function public.guard_service_history()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
declare received numeric(12,2);
begin
  select coalesce(sum(amount),0) into received from public.service_payments where service_id=old.id;
  if new.amount<received then raise exception 'O valor total não pode ser menor que o valor já recebido (%).',received;end if;
  if old.status<>'scheduled' and (
    new.client_id is distinct from old.client_id or new.address_id is distinct from old.address_id or
    new.quantity is distinct from old.quantity or new.scheduled_delivery_date is distinct from old.scheduled_delivery_date or
    new.amount is distinct from old.amount or new.delivered_at is distinct from old.delivered_at or
    new.deadline_date is distinct from old.deadline_date
  ) then raise exception 'Após a entrega, somente informações administrativas podem ser editadas';end if;
  return new;
end$$;
drop trigger if exists services_history_guard on public.services;
create trigger services_history_guard before update on public.services for each row execute function public.guard_service_history();
notify pgrst,'reload schema';
