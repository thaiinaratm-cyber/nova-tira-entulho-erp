-- Pagamentos parciais por Ordem de Serviço.
-- Migration transacional: substitui o enum com segurança sem apagar dados.

alter type public.payment_status rename to payment_status_legacy;
create type public.payment_status as enum ('pending','partial','paid');
alter table public.services alter column payment_status drop default;
alter table public.services alter column payment_status type public.payment_status using payment_status::text::public.payment_status;
alter table public.services alter column payment_status set default 'pending'::public.payment_status;
drop type public.payment_status_legacy;

create table public.service_payments(
  id uuid primary key default gen_random_uuid(),
  company_id uuid not null references public.companies(id),
  service_id uuid not null references public.services(id) on delete cascade,
  amount numeric(12,2) not null check(amount > 0),
  payment_method text not null check(payment_method in ('Pix','Dinheiro','Cartão','Transferência','Boleto','Outro')),
  paid_at timestamptz not null default now(),
  notes text,
  created_by uuid references public.profiles(id) on delete set null,
  created_at timestamptz not null default now()
);

create index service_payments_service_paid_idx on public.service_payments(service_id,paid_at desc);
create index service_payments_company_idx on public.service_payments(company_id);
create index service_payments_created_by_idx on public.service_payments(created_by);

alter table public.service_payments enable row level security;
create policy service_payments_select on public.service_payments for select to authenticated using(company_id=public.current_company_id());
create policy service_payments_insert on public.service_payments for insert to authenticated with check(company_id=public.current_company_id() and (created_by is null or created_by=auth.uid()));
create policy service_payments_update on public.service_payments for update to authenticated using(company_id=public.current_company_id()) with check(company_id=public.current_company_id());
create policy service_payments_delete on public.service_payments for delete to authenticated using(company_id=public.current_company_id());
grant select,insert,update,delete on public.service_payments to authenticated;

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
  return new;
end$$;

create or replace function public.sync_service_payment_status()
returns trigger language plpgsql security definer set search_path=public set row_security=off as $$
declare target_service uuid;service_amount numeric(12,2);received numeric(12,2);next_status public.payment_status;
begin
  target_service=coalesce(new.service_id,old.service_id);
  select amount into service_amount from public.services where id=target_service;
  select coalesce(sum(amount),0) into received from public.service_payments where service_id=target_service;
  next_status=case when received<=0 then 'pending'::public.payment_status when received<service_amount then 'partial'::public.payment_status else 'paid'::public.payment_status end;
  update public.services set payment_status=next_status where id=target_service;
  return coalesce(new,old);
end$$;

create trigger service_payments_guard before insert or update on public.service_payments for each row execute function public.guard_service_payment();
create trigger service_payments_sync after insert or update or delete on public.service_payments for each row execute function public.sync_service_payment_status();

-- Preserva OS antigas que já estavam marcadas como pagas.
insert into public.service_payments(company_id,service_id,amount,payment_method,paid_at,notes,created_by)
select company_id,id,amount,payment_method,coalesce(delivered_at,created_at),'Pagamento integral anterior à implantação do histórico',null
from public.services
where payment_status='paid' and amount>0 and not exists(select 1 from public.service_payments p where p.service_id=services.id);

-- Normaliza qualquer OS sem lançamento.
update public.services s set payment_status=case
 when coalesce((select sum(p.amount) from public.service_payments p where p.service_id=s.id),0)=0 then 'pending'::public.payment_status
 when coalesce((select sum(p.amount) from public.service_payments p where p.service_id=s.id),0)<s.amount then 'partial'::public.payment_status
 else 'paid'::public.payment_status end;