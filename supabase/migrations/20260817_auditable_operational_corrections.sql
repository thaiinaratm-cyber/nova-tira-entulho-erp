begin;

create table if not exists public.service_dumpster_events (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  service_id uuid not null references public.services(id),
  dumpster_id uuid references public.service_dumpsters(id),
  event_type text not null check (event_type in ('dumpster_cancelled','delivery_reversed','service_cancelled')),
  previous_status text not null,
  new_status text not null,
  reason text,
  performed_by uuid references public.profiles(id) on delete set null,
  performed_by_name text,
  occurred_at timestamptz not null default now()
);

create index if not exists service_dumpster_events_service_idx
  on public.service_dumpster_events(company_id,service_id,occurred_at desc);
create index if not exists service_dumpster_events_dumpster_idx
  on public.service_dumpster_events(dumpster_id,occurred_at desc);

alter table public.service_dumpster_events enable row level security;
drop policy if exists service_dumpster_events_company_select on public.service_dumpster_events;
create policy service_dumpster_events_company_select on public.service_dumpster_events
  for select to authenticated using (company_id=public.current_company_id());
revoke all on public.service_dumpster_events from public,authenticated;
grant select on public.service_dumpster_events to authenticated;

drop function if exists public.cancel_service_dumpster(uuid);
create function public.cancel_service_dumpster(dumpster_id uuid,cancellation_reason text default null)
returns public.service_dumpsters language plpgsql security definer set search_path=public set row_security=off as $$
declare item public.service_dumpsters; old_status text; actor_name text;
begin
  select * into item from public.service_dumpsters
   where id=dumpster_id and company_id=public.current_company_id() for update;
  if not found then raise exception 'Caçamba não encontrada ou sem acesso'; end if;
  if item.status not in ('scheduled','delivered','waiting_collection') then
    raise exception 'Somente caçambas ainda não retiradas podem ser canceladas';
  end if;
  old_status:=item.status;
  select full_name into actor_name from public.profiles where id=auth.uid();
  update public.service_dumpsters set status='cancelled' where id=item.id returning * into item;
  insert into public.service_dumpster_events(company_id,service_id,dumpster_id,event_type,previous_status,new_status,reason,performed_by,performed_by_name)
  values(item.company_id,item.service_id,item.id,'dumpster_cancelled',old_status,'cancelled',nullif(trim(cancellation_reason),''),auth.uid(),actor_name);
  delete from public.notifications where company_id=item.company_id and related_id=item.service_id
    and deduplication_key like '%:dumpster:'||item.id||'%';
  return item;
end $$;

create or replace function public.reverse_dumpster_delivery(dumpster_id uuid,reversal_reason text)
returns public.service_dumpsters language plpgsql security definer set search_path=public set row_security=off as $$
declare item public.service_dumpsters; old_status text; actor_name text;
begin
  if not public.current_user_is_admin() then raise exception 'Somente administradores podem estornar uma entrega'; end if;
  if nullif(trim(reversal_reason),'') is null then raise exception 'Informe o motivo do estorno'; end if;
  select * into item from public.service_dumpsters
   where id=dumpster_id and company_id=public.current_company_id() for update;
  if not found then raise exception 'Caçamba não encontrada ou sem acesso'; end if;
  if item.status not in ('delivered','waiting_collection') or item.collected_at is not null then
    raise exception 'Esta entrega não pode ser estornada no estado atual';
  end if;
  old_status:=item.status;
  select full_name into actor_name from public.profiles where id=auth.uid();
  update public.service_dumpsters set status='scheduled',delivered_at=null,deadline_at=null,
    collection_requested_at=null,collected_at=null where id=item.id returning * into item;
  insert into public.service_dumpster_events(company_id,service_id,dumpster_id,event_type,previous_status,new_status,reason,performed_by,performed_by_name)
  values(item.company_id,item.service_id,item.id,'delivery_reversed',old_status,'scheduled',trim(reversal_reason),auth.uid(),actor_name);
  delete from public.notifications where company_id=item.company_id and related_id=item.service_id
    and type in ('collection_today','deadline_soon','overdue')
    and deduplication_key like '%:dumpster:'||item.id||'%';
  return item;
end $$;

create or replace function public.cancel_service_order(service_id uuid,cancellation_reason text)
returns public.services language plpgsql security definer set search_path=public set row_security=off as $$
declare target public.services; result public.services; actor_name text; unit record;
begin
  if not public.current_user_is_admin() then raise exception 'Somente administradores podem cancelar uma OS'; end if;
  if nullif(trim(cancellation_reason),'') is null then raise exception 'Informe o motivo do cancelamento'; end if;
  select * into target from public.services where id=service_id and company_id=public.current_company_id() for update;
  if not found then raise exception 'OS não encontrada ou sem acesso'; end if;
  if target.status in ('completed','cancelled') then raise exception 'A OS já está finalizada ou cancelada'; end if;
  select full_name into actor_name from public.profiles where id=auth.uid();
  for unit in select id,status from public.service_dumpsters where service_id=target.id and status in ('scheduled','delivered','waiting_collection') for update loop
    insert into public.service_dumpster_events(company_id,service_id,dumpster_id,event_type,previous_status,new_status,reason,performed_by,performed_by_name)
    values(target.company_id,target.id,unit.id,'dumpster_cancelled',unit.status,'cancelled',trim(cancellation_reason),auth.uid(),actor_name);
  end loop;
  update public.service_dumpsters set status='cancelled'
    where service_id=target.id and status in ('scheduled','delivered','waiting_collection');
  update public.services set status='cancelled' where id=target.id returning * into result;
  insert into public.service_dumpster_events(company_id,service_id,event_type,previous_status,new_status,reason,performed_by,performed_by_name)
  values(target.company_id,target.id,'service_cancelled',target.status,'cancelled',trim(cancellation_reason),auth.uid(),actor_name);
  delete from public.notifications where company_id=target.company_id and related_type='service' and related_id=target.id;
  return result;
end $$;

revoke all on function public.cancel_service_dumpster(uuid,text) from public;
revoke all on function public.reverse_dumpster_delivery(uuid,text) from public;
revoke all on function public.cancel_service_order(uuid,text) from public;
grant execute on function public.cancel_service_dumpster(uuid,text) to authenticated;
grant execute on function public.reverse_dumpster_delivery(uuid,text) to authenticated;
grant execute on function public.cancel_service_order(uuid,text) to authenticated;

notify pgrst,'reload schema';

commit;
