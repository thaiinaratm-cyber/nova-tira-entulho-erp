-- Central de notificações V1: geração idempotente sem dependência de cron externo.
create table if not exists public.notifications(
 id uuid primary key default gen_random_uuid(),
 company_id uuid not null references public.companies(id),
 user_id uuid references public.profiles(id) on delete cascade,
 type text not null check(type in ('delivery_today','collection_today','deadline_soon','overdue','payment_pending','low_availability')),
 title text not null,
 message text not null,
 related_type text,
 related_id uuid,
 action_url text,
 is_read boolean not null default false,
 deduplication_key text,
 created_at timestamptz not null default now(),
 read_at timestamptz,
 constraint notifications_read_consistency check((is_read=false and read_at is null) or is_read=true)
);

create index if not exists notifications_user_unread_idx on public.notifications(user_id,is_read,created_at desc);
create index if not exists notifications_company_created_idx on public.notifications(company_id,created_at desc);
create index if not exists notifications_related_idx on public.notifications(related_type,related_id);
create unique index if not exists notifications_user_dedup_idx on public.notifications(user_id,deduplication_key) where deduplication_key is not null;
alter table public.notifications enable row level security;

drop policy if exists notifications_select_own on public.notifications;
drop policy if exists notifications_update_own on public.notifications;
create policy notifications_select_own on public.notifications for select to authenticated
using(company_id=public.current_company_id() and (user_id=auth.uid() or user_id is null));
create policy notifications_update_own on public.notifications for update to authenticated
using(company_id=public.current_company_id() and user_id=auth.uid())
with check(company_id=public.current_company_id() and user_id=auth.uid());

revoke all on public.notifications from authenticated;
grant select,update(is_read,read_at) on public.notifications to authenticated;

create or replace function public.generate_operational_notifications()
returns integer language plpgsql security definer set search_path=public set row_security=off as $$
declare
 company uuid:=public.current_company_id();
 generated integer:=0;
 affected integer:=0;
 today_key date:=(now() at time zone 'America/Sao_Paulo')::date;
 now_at timestamptz:=now();
 deadline_at timestamptz;
 received numeric(12,2);
 balance numeric(12,2);
 total_dumpsters integer:=0;
 low_threshold integer:=10;
 committed integer:=0;
 available integer:=0;
 service record;
begin
 if company is null then raise exception 'Usuário sem empresa ativa';end if;

 insert into public.settings(company_id,key,value)
 values(company,'low_dumpster_threshold','10'::jsonb)
 on conflict(company_id,key) do nothing;

 select coalesce((value#>>'{}')::integer,0) into total_dumpsters from public.settings where company_id=company and key='total_dumpsters';
 select coalesce((value#>>'{}')::integer,10) into low_threshold from public.settings where company_id=company and key='low_dumpster_threshold';

 for service in
  select s.*,coalesce(c.name,'Cliente') client_name
  from public.services s join public.clients c on c.id=s.client_id
  where s.company_id=company and s.status<>'cancelled'
 loop
  deadline_at:=case when service.delivered_at is not null then service.delivered_at+interval '7 days' when service.deadline_date is not null then (service.deadline_date::timestamp+interval '23 hours 59 minutes') at time zone 'America/Sao_Paulo' end;

  if service.status='scheduled' and service.scheduled_delivery_date=today_key then
   insert into public.notifications(company_id,user_id,type,title,message,related_type,related_id,action_url,deduplication_key)
   select company,p.id,'delivery_today','Entrega programada para hoje',service.service_number||' · '||service.client_name||' · '||service.quantity||case when service.quantity=1 then ' caçamba' else ' caçambas' end,'service',service.id,'/servicos/'||service.id,'delivery_today:'||service.id||':'||today_key
   from public.profiles p where p.company_id=company and p.is_active=true
   on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;
   get diagnostics affected=row_count;generated:=generated+affected;
  end if;

  if service.status in ('delivered','waiting_collection') and deadline_at is not null then
   if (deadline_at at time zone 'America/Sao_Paulo')::date=today_key then
    insert into public.notifications(company_id,user_id,type,title,message,related_type,related_id,action_url,deduplication_key)
    select company,p.id,'collection_today','Retirada prevista para hoje',service.service_number||' · '||service.client_name,'service',service.id,'/servicos/'||service.id,'collection_today:'||service.id||':'||today_key
    from public.profiles p where p.company_id=company and p.is_active=true
    on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;
    get diagnostics affected=row_count;generated:=generated+affected;
   end if;

   if deadline_at>now_at and deadline_at<=now_at+interval '24 hours' then
    insert into public.notifications(company_id,user_id,type,title,message,related_type,related_id,action_url,deduplication_key)
    select company,p.id,'deadline_soon','Prazo de retirada próximo',service.service_number||' vence em '||to_char(deadline_at at time zone 'America/Sao_Paulo','DD/MM/YYYY "às" HH24:MI'),'service',service.id,'/servicos/'||service.id,'deadline_24h:'||service.id
    from public.profiles p where p.company_id=company and p.is_active=true
    on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;
    get diagnostics affected=row_count;generated:=generated+affected;
   end if;

   if deadline_at<=now_at then
    insert into public.notifications(company_id,user_id,type,title,message,related_type,related_id,action_url,deduplication_key)
    select company,p.id,'overdue','Retirada atrasada',service.service_number||' está atrasada há '||case when extract(epoch from(now_at-deadline_at))<3600 then 'menos de 1h' when extract(epoch from(now_at-deadline_at))<86400 then floor(extract(epoch from(now_at-deadline_at))/3600)::int||'h' else floor(extract(epoch from(now_at-deadline_at))/86400)::int||' dia(s) e '||floor(mod(extract(epoch from(now_at-deadline_at)),86400)/3600)::int||'h' end,'service',service.id,'/servicos/'||service.id,'overdue:'||service.id||':'||today_key
    from public.profiles p where p.company_id=company and p.is_active=true
    on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;
    get diagnostics affected=row_count;generated:=generated+affected;
   end if;
  end if;

  select coalesce(sum(sp.amount),0) into received from public.service_payments sp where sp.service_id=service.id;
  balance:=greatest(0,service.amount-received);
  if balance>0 and (service.status='completed' or (service.status in ('delivered','waiting_collection') and deadline_at<=now_at+interval '24 hours')) then
   insert into public.notifications(company_id,user_id,type,title,message,related_type,related_id,action_url,deduplication_key)
   select company,p.id,'payment_pending','Pagamento pendente',service.service_number||' possui saldo de R$ '||to_char(balance,'FM999999990D00'),'service',service.id,'/servicos/'||service.id,'payment_pending:'||service.id
   from public.profiles p where p.company_id=company and p.is_active=true and p.role='admin'
   on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;
   get diagnostics affected=row_count;generated:=generated+affected;
  end if;
 end loop;

 select coalesce(sum(quantity),0) into committed from public.services where company_id=company and status in ('scheduled','delivered','waiting_collection');
 available:=greatest(0,total_dumpsters-committed);
 if total_dumpsters>0 and available<=low_threshold then
  insert into public.notifications(company_id,user_id,type,title,message,related_type,action_url,deduplication_key)
  select company,p.id,'low_availability','Baixa disponibilidade de caçambas','Restam apenas '||available||' caçambas disponíveis.','availability','/disponibilidade','low_availability:'||today_key||':'||available
  from public.profiles p where p.company_id=company and p.is_active=true and p.role='admin'
  on conflict(user_id,deduplication_key) where deduplication_key is not null do nothing;
  get diagnostics affected=row_count;generated:=generated+affected;
 end if;
 return generated;
end $$;

revoke all on function public.generate_operational_notifications() from public;
grant execute on function public.generate_operational_notifications() to authenticated;
notify pgrst,'reload schema';
