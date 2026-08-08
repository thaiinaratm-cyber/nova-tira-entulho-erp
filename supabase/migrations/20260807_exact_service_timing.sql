-- Timestamps autoritativos para o ciclo de entrega e retirada.
create or replace function public.confirm_delivery(service_id uuid)
returns public.services
language plpgsql
security definer
set search_path=public
as $$
declare result public.services;
begin
  update public.services
     set delivered_at=now(),
         deadline_date=(now()+interval '7 days')::date,
         status='delivered'
   where id=service_id
     and company_id=public.current_company_id()
     and status='scheduled'
  returning * into result;
  if result.id is null then raise exception 'Serviço inválido ou já entregue'; end if;
  return result;
end;
$$;

create or replace function public.confirm_collection(service_id uuid)
returns public.services
language plpgsql
security definer
set search_path=public
as $$
declare result public.services;
begin
  update public.services
     set collected_at=now(),
         status='completed'
   where id=service_id
     and company_id=public.current_company_id()
     and status='waiting_collection'
     and delivered_at is not null
  returning * into result;
  if result.id is null then raise exception 'Serviço inválido ou não está aguardando retirada'; end if;
  return result;
end;
$$;

revoke all on function public.confirm_delivery(uuid) from public;
revoke all on function public.confirm_collection(uuid) from public;
grant execute on function public.confirm_delivery(uuid) to authenticated;
grant execute on function public.confirm_collection(uuid) to authenticated;
