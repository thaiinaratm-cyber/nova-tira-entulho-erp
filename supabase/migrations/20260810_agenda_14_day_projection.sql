-- Alinha a projeção diária: retiradas previstas até a data voltam a ficar disponíveis.
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
notify pgrst,'reload schema';
