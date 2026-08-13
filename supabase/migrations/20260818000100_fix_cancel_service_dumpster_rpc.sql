begin;

-- Esta migration é autossuficiente porque alguns ambientes receberam a tabela
-- service_dumpsters, mas ainda não receberam a estrutura de auditoria.
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
  for select to authenticated
  using (company_id=public.current_company_id());

revoke all on public.service_dumpster_events from public,authenticated;
grant select on public.service_dumpster_events to authenticated;

-- Assinatura que o PostgREST deve publicar:
-- public.cancel_service_dumpster(dumpster_id uuid, cancellation_reason text)
-- The previous version has DEFAULT NULL on cancellation_reason. PostgreSQL
-- cannot remove that default with CREATE OR REPLACE, so only this exact
-- signature is dropped before it is recreated with a required parameter.
drop function if exists public.cancel_service_dumpster(uuid,text);

create function public.cancel_service_dumpster(
  dumpster_id uuid,
  cancellation_reason text
)
returns public.service_dumpsters
language plpgsql
security definer
set search_path=public
set row_security=off
as $$
declare
  company uuid;
  item public.service_dumpsters;
  old_status text;
  actor_name text;
begin
  if auth.uid() is null then
    raise exception 'Usuário não autenticado';
  end if;

  company:=public.current_company_id();
  if company is null then
    raise exception 'Usuário autenticado sem empresa associada';
  end if;

  select * into item
    from public.service_dumpsters
   where id=dumpster_id
     and company_id=company
   for update;

  if not found then
    raise exception 'Caçamba não encontrada ou não pertence à empresa do usuário';
  end if;

  if item.status not in ('scheduled','delivered','waiting_collection') then
    raise exception 'Somente caçambas ainda não retiradas podem ser canceladas';
  end if;

  old_status:=item.status;
  select full_name into actor_name from public.profiles where id=auth.uid();

  update public.service_dumpsters
     set status='cancelled'
   where id=item.id
   returning * into item;

  insert into public.service_dumpster_events(
    company_id,service_id,dumpster_id,event_type,previous_status,new_status,
    reason,performed_by,performed_by_name,occurred_at
  ) values (
    item.company_id,item.service_id,item.id,'dumpster_cancelled',old_status,
    'cancelled',nullif(trim(cancellation_reason),''),auth.uid(),actor_name,now()
  );

  -- Remove alertas operacionais da unidade que deixou de estar ativa.
  delete from public.notifications
   where company_id=item.company_id
     and related_type='service'
     and related_id=item.service_id
     and deduplication_key like '%:dumpster:'||item.id||'%';

  -- O trigger existente já sincroniza a OS; esta chamada torna a atualização
  -- explícita e também cobre bancos onde o trigger tenha sido recriado depois.
  perform public.sync_service_from_dumpsters(item.service_id);

  return item;
end
$$;

revoke all on function public.cancel_service_dumpster(uuid,text) from public;
grant execute on function public.cancel_service_dumpster(uuid,text) to authenticated;

comment on function public.cancel_service_dumpster(uuid,text) is
  'Cancela uma caçamba da empresa autenticada sem exclusão física e registra auditoria.';

-- Solicita ao PostgREST/Supabase a atualização imediata das funções expostas.
notify pgrst,'reload schema';

commit;
