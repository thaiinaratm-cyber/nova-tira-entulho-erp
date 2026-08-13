-- Unidades operacionais individuais dentro de uma mesma Ordem de Serviço.
-- A OS continua sendo o cabeçalho financeiro e documental.

create table if not exists public.service_dumpsters (
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  service_id uuid not null references public.services(id) on delete cascade,
  delivery_scheduled_at timestamptz not null,
  delivered_at timestamptz,
  deadline_at timestamptz,
  collection_requested_at timestamptz,
  collected_at timestamptz,
  status text not null default 'scheduled' check(status in ('scheduled','delivered','waiting_collection','collected','cancelled')),
  value numeric(12,2) check(value is null or value >= 0),
  notes text,
  created_at timestamptz not null default now(),
  created_by uuid references public.profiles(id) on delete set null,
  constraint service_dumpsters_timeline_check check(
    (delivered_at is null or deadline_at is not null)
    and (collected_at is null or delivered_at is not null)
  )
);

create index if not exists service_dumpsters_service_idx on public.service_dumpsters(service_id,created_at);
create index if not exists service_dumpsters_company_status_idx on public.service_dumpsters(company_id,status);
create index if not exists service_dumpsters_delivery_idx on public.service_dumpsters(company_id,delivery_scheduled_at) where status='scheduled';
create index if not exists service_dumpsters_deadline_idx on public.service_dumpsters(company_id,deadline_at) where status in ('delivered','waiting_collection');

alter table public.service_dumpsters enable row level security;
drop policy if exists service_dumpsters_company on public.service_dumpsters;
create policy service_dumpsters_company on public.service_dumpsters for all to authenticated
using(company_id=public.current_company_id()) with check(company_id=public.current_company_id());
grant select,insert,update on public.service_dumpsters to authenticated;

-- Converte cada unidade de quantity em uma linha, sem alterar a OS, pagamentos ou recibos.
insert into public.service_dumpsters(
  company_id,service_id,delivery_scheduled_at,delivered_at,deadline_at,
  collection_requested_at,collected_at,status,value,notes,created_at
)
select s.company_id,s.id,
  (s.scheduled_delivery_date::timestamp + time '12:00') at time zone 'America/Sao_Paulo',
  s.delivered_at,
  case when s.delivered_at is not null then s.delivered_at+interval '7 days'
       when s.deadline_date is not null then (s.deadline_date::timestamp+time '23:59') at time zone 'America/Sao_Paulo' end,
  case when s.status='waiting_collection' then s.updated_at end,
  s.collected_at,
  case s.status when 'completed' then 'collected' else s.status::text end,
  round(s.amount/greatest(s.quantity,1),2),s.notes,s.created_at
from public.services s
cross join lateral generate_series(1,greatest(s.quantity,1)) unit
where not exists(select 1 from public.service_dumpsters d where d.service_id=s.id);

create or replace function public.sync_service_from_dumpsters(target_service_id uuid)
returns void language plpgsql security definer set search_path=public set row_security=off as $$
declare summary record;
begin
  select
    count(*) filter(where status<>'cancelled')::integer quantity,
    min(delivery_scheduled_at)::date scheduled_date,
    min(delivered_at) delivered_at,
    min(deadline_at)::date deadline_date,
    max(collected_at) collected_at,
    case
      when count(*) filter(where status='waiting_collection')>0 then 'waiting_collection'::public.service_status
      when count(*) filter(where status='delivered')>0 then 'delivered'::public.service_status
      when count(*) filter(where status='scheduled')>0 then 'scheduled'::public.service_status
      when count(*) filter(where status='collected')>0 then 'completed'::public.service_status
      else 'cancelled'::public.service_status
    end status
  into summary from public.service_dumpsters where service_id=target_service_id;
  update public.services set
    quantity=greatest(summary.quantity,1),
    scheduled_delivery_date=coalesce(summary.scheduled_date,scheduled_delivery_date),
    delivered_at=summary.delivered_at,
    deadline_date=summary.deadline_date,
    collected_at=case when summary.status='completed' then summary.collected_at else null end,
    status=summary.status
  where id=target_service_id;
end $$;

create or replace function public.sync_service_after_dumpster_change()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
begin perform public.sync_service_from_dumpsters(coalesce(new.service_id,old.service_id));return coalesce(new,old);end $$;
drop trigger if exists service_dumpsters_sync_service on public.service_dumpsters;
create trigger service_dumpsters_sync_service after insert or update or delete on public.service_dumpsters
for each row execute function public.sync_service_after_dumpster_change();

create or replace function public.create_dumpsters_for_new_service()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
begin
  if not exists(select 1 from public.service_dumpsters where service_id=new.id) then
    insert into public.service_dumpsters(company_id,service_id,delivery_scheduled_at,status,value,notes,created_by)
    select new.company_id,new.id,(new.scheduled_delivery_date::timestamp+time '12:00') at time zone 'America/Sao_Paulo',
      'scheduled',round(new.amount/greatest(new.quantity,1),2),new.notes,auth.uid()
    from generate_series(1,greatest(new.quantity,1));
  end if;
  return new;
end $$;
drop trigger if exists services_create_dumpsters on public.services;
create trigger services_create_dumpsters after insert on public.services
for each row execute function public.create_dumpsters_for_new_service();

create or replace function public.projected_dumpster_availability(target_date date,exclude_service_id uuid default null)
returns integer language sql stable security definer set search_path=public set row_security=off as $$
with capacity as(
 select coalesce((value#>>'{}')::integer,0) total from public.settings
 where company_id=public.current_company_id() and key='total_dumpsters'
), used as(
 select count(*)::integer quantity from public.service_dumpsters d
 where d.company_id=public.current_company_id()
 and (exclude_service_id is null or d.service_id<>exclude_service_id)
 and ((d.status='scheduled' and d.delivery_scheduled_at::date<=target_date and d.delivery_scheduled_at+interval '7 days'>target_date::timestamp)
   or (d.status in ('delivered','waiting_collection') and coalesce(d.deadline_at,now()+interval '100 years')>target_date::timestamp))
)
select greatest(0,coalesce(capacity.total,0)-used.quantity) from capacity cross join used
$$;

create or replace function public.guard_dumpster_inventory()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
declare total integer;committed integer;
begin
 if new.status in ('scheduled','delivered','waiting_collection') then
  select coalesce((value#>>'{}')::integer,0) into total from public.settings where company_id=new.company_id and key='total_dumpsters';
  select count(*) into committed from public.service_dumpsters where company_id=new.company_id
   and status in ('scheduled','delivered','waiting_collection') and id<>new.id;
  if committed+1>coalesce(total,0) then raise exception 'Quantidade de caçambas indisponível';end if;
 end if;return new;
end $$;
drop trigger if exists services_inventory_guard on public.services;
drop trigger if exists service_dumpsters_inventory_guard on public.service_dumpsters;
create trigger service_dumpsters_inventory_guard before insert or update on public.service_dumpsters
for each row execute function public.guard_dumpster_inventory();

-- O cabeçalho não controla mais quantidade/prazos manualmente; esses campos são sincronizados pelas unidades.
create or replace function public.guard_service_history()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
declare received numeric(12,2);
begin
 select coalesce(sum(amount),0) into received from public.service_payments where service_id=old.id;
 if new.amount<received then raise exception 'O valor total não pode ser menor que o valor já recebido (%).',received;end if;
 if pg_trigger_depth()=1 and new.quantity is distinct from old.quantity then
  raise exception 'A quantidade é derivada das caçambas da OS. Use Adicionar caçamba ou cancele uma unidade agendada.';
 end if;
 if old.status<>'scheduled' and (new.client_id is distinct from old.client_id or new.address_id is distinct from old.address_id) then
  raise exception 'Após a entrega, cliente e endereço da obra não podem ser alterados';
 end if;
 return new;
end $$;

create or replace function public.add_service_dumpsters(service_id uuid,delivery_scheduled_at timestamptz,additional_amount numeric default 0,dumpster_notes text default null,dumpster_count integer default 1)
returns setof public.service_dumpsters language plpgsql security definer set search_path=public set row_security=off as $$
declare target public.services;item public.service_dumpsters;i integer;
begin
 if dumpster_count<1 then raise exception 'Informe ao menos uma caçamba';end if;
 if additional_amount<0 then raise exception 'O valor adicional não pode ser negativo';end if;
 select * into target from public.services where id=service_id and company_id=public.current_company_id()
 and status in ('scheduled','delivered','waiting_collection') for update;
 if target.id is null then raise exception 'OS inexistente, de outra empresa ou encerrada';end if;
 update public.services set amount=amount+additional_amount where id=target.id;
 for i in 1..dumpster_count loop
  insert into public.service_dumpsters(company_id,service_id,delivery_scheduled_at,status,value,notes,created_by)
  values(target.company_id,target.id,delivery_scheduled_at,'scheduled',round(additional_amount/dumpster_count,2),dumpster_notes,auth.uid()) returning * into item;
  return next item;
 end loop;return;
end $$;

create or replace function public.confirm_dumpster_delivery(dumpster_id uuid)
returns public.service_dumpsters language plpgsql security definer set search_path=public set row_security=off as $$
declare result public.service_dumpsters;
begin update public.service_dumpsters set delivered_at=now(),deadline_at=now()+interval '7 days',status='delivered'
 where id=dumpster_id and company_id=public.current_company_id() and status='scheduled' returning * into result;
 if result.id is null then raise exception 'Caçamba inválida, de outra empresa ou não agendada';end if;return result;end $$;

create or replace function public.request_dumpster_collection(dumpster_id uuid)
returns public.service_dumpsters language plpgsql security definer set search_path=public set row_security=off as $$
declare result public.service_dumpsters;
begin update public.service_dumpsters set collection_requested_at=now(),status='waiting_collection'
 where id=dumpster_id and company_id=public.current_company_id() and status='delivered' returning * into result;
 if result.id is null then raise exception 'Caçamba inválida, de outra empresa ou não entregue';end if;return result;end $$;

create or replace function public.confirm_dumpster_collection(dumpster_id uuid)
returns public.service_dumpsters language plpgsql security definer set search_path=public set row_security=off as $$
declare result public.service_dumpsters;
begin update public.service_dumpsters set collected_at=now(),status='collected'
 where id=dumpster_id and company_id=public.current_company_id() and status='waiting_collection' returning * into result;
 if result.id is null then raise exception 'Caçamba inválida, de outra empresa ou não aguardando retirada';end if;return result;end $$;

create or replace function public.cancel_service_dumpster(dumpster_id uuid)
returns public.service_dumpsters language plpgsql security definer set search_path=public set row_security=off as $$
declare result public.service_dumpsters;
begin update public.service_dumpsters set status='cancelled'
 where id=dumpster_id and company_id=public.current_company_id() and status='scheduled' returning * into result;
 if result.id is null then raise exception 'Somente caçamba agendada pode ser cancelada';end if;return result;end $$;

revoke all on function public.add_service_dumpsters(uuid,timestamptz,numeric,text,integer) from public;
revoke all on function public.confirm_dumpster_delivery(uuid) from public;
revoke all on function public.request_dumpster_collection(uuid) from public;
revoke all on function public.confirm_dumpster_collection(uuid) from public;
revoke all on function public.cancel_service_dumpster(uuid) from public;
grant execute on function public.add_service_dumpsters(uuid,timestamptz,numeric,text,integer) to authenticated;
grant execute on function public.confirm_dumpster_delivery(uuid) to authenticated;
grant execute on function public.request_dumpster_collection(uuid) to authenticated;
grant execute on function public.confirm_dumpster_collection(uuid) to authenticated;
grant execute on function public.cancel_service_dumpster(uuid) to authenticated;
grant execute on function public.projected_dumpster_availability(date,uuid) to authenticated;

-- Alertas operacionais passam a usar a unidade, com chave de deduplicação por caçamba.
create or replace function public.generate_operational_notifications()
returns integer language plpgsql security definer set search_path=public set row_security=off as $$
declare company uuid:=public.current_company_id();generated integer:=0;affected integer:=0;today_key date:=(now() at time zone 'America/Sao_Paulo')::date;now_at timestamptz:=now();item record;service record;received numeric(12,2);balance numeric(12,2);total_dumpsters integer:=0;low_threshold integer:=10;available integer:=0;
begin
 if company is null then raise exception 'Usuário sem empresa ativa';end if;
 insert into public.settings(company_id,key,value) values(company,'low_dumpster_threshold','10'::jsonb) on conflict(company_id,key) do nothing;
 select coalesce((value#>>'{}')::integer,0) into total_dumpsters from public.settings where company_id=company and key='total_dumpsters';
 select coalesce((value#>>'{}')::integer,10) into low_threshold from public.settings where company_id=company and key='low_dumpster_threshold';
 for item in select d.*,s.service_number,s.id service_id,c.name client_name,row_number() over(partition by s.id order by d.created_at,d.id) unit_number from public.service_dumpsters d join public.services s on s.id=d.service_id join public.clients c on c.id=s.client_id where d.company_id=company and d.status in ('scheduled','delivered','waiting_collection') loop
  if item.status='scheduled' and (item.delivery_scheduled_at at time zone 'America/Sao_Paulo')::date=today_key then
   insert into public.notifications(company_id,user_id,type,title,message,related_type,related_id,action_url,deduplication_key)
   select company,p.id,'delivery_today','Entrega programada para hoje',item.service_number||' · '||item.client_name||' · Caçamba '||item.unit_number,'service',item.service_id,'/servicos/'||item.service_id,'delivery_today:dumpster:'||item.id||':'||today_key from public.profiles p where p.company_id=company and p.is_active=true on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;get diagnostics affected=row_count;generated:=generated+affected;
  end if;
  if item.status in ('delivered','waiting_collection') and item.deadline_at is not null then
   if (item.deadline_at at time zone 'America/Sao_Paulo')::date=today_key then
    insert into public.notifications(company_id,user_id,type,title,message,related_type,related_id,action_url,deduplication_key)
    select company,p.id,'collection_today','Retirada prevista para hoje',item.service_number||' · '||item.client_name||' · Caçamba '||item.unit_number,'service',item.service_id,'/servicos/'||item.service_id,'collection_today:dumpster:'||item.id||':'||today_key from public.profiles p where p.company_id=company and p.is_active=true on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;get diagnostics affected=row_count;generated:=generated+affected;
   end if;
   if item.deadline_at>now_at and item.deadline_at<=now_at+interval '24 hours' then
    insert into public.notifications(company_id,user_id,type,title,message,related_type,related_id,action_url,deduplication_key)
    select company,p.id,'deadline_soon','Prazo da caçamba próximo',item.service_number||' · '||item.client_name||' · Caçamba '||item.unit_number||' vence amanhã às '||to_char(item.deadline_at at time zone 'America/Sao_Paulo','HH24:MI'),'service',item.service_id,'/servicos/'||item.service_id,'deadline_24h:dumpster:'||item.id from public.profiles p where p.company_id=company and p.is_active=true on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;get diagnostics affected=row_count;generated:=generated+affected;
   elsif item.deadline_at<=now_at then
    insert into public.notifications(company_id,user_id,type,title,message,related_type,related_id,action_url,deduplication_key)
    select company,p.id,'overdue','Retirada atrasada',item.service_number||' · Caçamba '||item.unit_number||' está atrasada','service',item.service_id,'/servicos/'||item.service_id,'overdue:dumpster:'||item.id||':'||today_key from public.profiles p where p.company_id=company and p.is_active=true on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;get diagnostics affected=row_count;generated:=generated+affected;
   end if;
  end if;
 end loop;
 for service in select * from public.services where company_id=company and status<>'cancelled' loop
  select coalesce(sum(amount),0) into received from public.service_payments where service_id=service.id;balance:=greatest(0,service.amount-received);
  if balance>0 and (service.status='completed' or exists(select 1 from public.service_dumpsters d where d.service_id=service.id and d.status in ('delivered','waiting_collection') and d.deadline_at<=now_at+interval '24 hours')) then
   insert into public.notifications(company_id,user_id,type,title,message,related_type,related_id,action_url,deduplication_key) select company,p.id,'payment_pending','Pagamento pendente',service.service_number||' possui saldo de R$ '||to_char(balance,'FM999999990D00'),'service',service.id,'/servicos/'||service.id,'payment_pending:'||service.id from public.profiles p where p.company_id=company and p.is_active=true and p.role='admin' on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;get diagnostics affected=row_count;generated:=generated+affected;
  end if;
 end loop;
 select greatest(0,total_dumpsters-count(*)) into available from public.service_dumpsters where company_id=company and status in ('scheduled','delivered','waiting_collection');
 if total_dumpsters>0 and available<=low_threshold then
  insert into public.notifications(company_id,user_id,type,title,message,related_type,action_url,deduplication_key) select company,p.id,'low_availability','Baixa disponibilidade de caçambas','Restam apenas '||available||' caçambas disponíveis.','availability','/disponibilidade','low_availability:'||today_key||':'||available from public.profiles p where p.company_id=company and p.is_active=true and p.role='admin' on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;get diagnostics affected=row_count;generated:=generated+affected;
 end if;return generated;
end $$;
revoke all on function public.generate_operational_notifications() from public;
grant execute on function public.generate_operational_notifications() to authenticated;

notify pgrst,'reload schema';
