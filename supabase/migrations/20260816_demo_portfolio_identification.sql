-- Identificação explícita e removível dos dados fictícios de portfólio.
alter table public.clients add column if not exists demo_batch text;
alter table public.services add column if not exists demo_batch text;
create index if not exists clients_demo_batch_idx on public.clients(company_id,demo_batch) where demo_batch is not null;
create index if not exists services_demo_batch_idx on public.services(company_id,demo_batch) where demo_batch is not null;

-- Recibos reais continuam imutáveis. Só recibos de OS explicitamente DEMO podem ser removidos pelo comando de limpeza.
create or replace function public.prevent_receipt_changes() returns trigger language plpgsql set search_path=public as $$
begin
 if tg_op='DELETE' and exists(select 1 from public.services s where s.id=old.service_id and s.demo_batch is not null) then return old;end if;
 raise exception 'Recibos emitidos são imutáveis';
end $$;
notify pgrst,'reload schema';
