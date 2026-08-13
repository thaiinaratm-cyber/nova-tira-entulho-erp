-- Recibos imutáveis vinculados a pagamentos de OS.
create sequence if not exists public.receipt_number_seq start 1;
create or replace function public.next_receipt_number() returns text language sql volatile security definer set search_path=public as $$select 'REC-'||lpad(nextval('public.receipt_number_seq')::text,6,'0')$$;

create table public.receipts(
 id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),receipt_number text not null unique default public.next_receipt_number(),service_id uuid not null references public.services(id),payment_id uuid not null unique references public.service_payments(id),client_id uuid not null references public.clients(id),amount numeric(12,2) not null,payment_method text not null,paid_at timestamptz not null,created_by uuid references public.profiles(id) on delete set null,created_at timestamptz not null default now(),
 service_number text not null,client_name text not null,client_document text,client_phone text not null,work_address text not null,company_name text not null,company_document text,company_address text,company_phone text,company_whatsapp text,company_logo_url text,payment_notes text,created_by_name text,service_total numeric(12,2) not null,received_through_payment numeric(12,2) not null,remaining_balance numeric(12,2) not null check(remaining_balance>=0),settlement_status text not null check(settlement_status in ('partial','paid'))
);
create index receipts_company_created_idx on public.receipts(company_id,created_at desc);create index receipts_service_idx on public.receipts(service_id);create index receipts_client_idx on public.receipts(client_id);create index receipts_payment_idx on public.receipts(payment_id);
alter table public.receipts enable row level security;
create policy receipts_select on public.receipts for select to authenticated using(company_id=public.current_company_id());
create policy receipts_insert on public.receipts for insert to authenticated with check(company_id=public.current_company_id() and (created_by is null or created_by=auth.uid()));
grant select,insert on public.receipts to authenticated;grant usage,select on sequence public.receipt_number_seq to authenticated;

create or replace function public.prevent_receipt_changes() returns trigger language plpgsql as $$begin raise exception 'Recibos emitidos são imutáveis';end$$;
create trigger receipts_immutable before update or delete on public.receipts for each row execute function public.prevent_receipt_changes();

create or replace function public.generate_receipt(target_payment_id uuid)
returns public.receipts language plpgsql security definer set search_path=public set row_security=off as $$
declare p public.service_payments;s public.services;c public.clients;co public.companies;a public.client_addresses;creator_name text;received numeric(12,2);balance numeric(12,2);result public.receipts;work text;company_addr text;
begin
 select * into result from receipts where payment_id=target_payment_id;
 if result.id is not null then if result.company_id<>current_company_id() then raise exception 'Acesso negado';end if;return result;end if;
 select * into p from service_payments where id=target_payment_id;
 if p.id is null or p.company_id<>current_company_id() then raise exception 'Pagamento não encontrado';end if;
 select * into s from services where id=p.service_id;select * into c from clients where id=s.client_id;select * into co from companies where id=p.company_id;select * into a from client_addresses where id=s.address_id;select full_name into creator_name from profiles where id=p.created_by;
 select coalesce(sum(sp.amount),0) into received from service_payments sp where sp.service_id=p.service_id and (sp.paid_at<p.paid_at or (sp.paid_at=p.paid_at and sp.created_at<p.created_at) or (sp.paid_at=p.paid_at and sp.created_at=p.created_at and sp.id<=p.id));
 balance=greatest(0,s.amount-received);
 work=concat_ws(', ',nullif(trim(a.address),''),nullif(trim(a.number),''));work=concat_ws(' - ',nullif(work,''),nullif(trim(a.neighborhood),''),nullif(concat_ws('/',nullif(trim(a.city),''),nullif(trim(a.state),'')),''));
 company_addr=concat_ws(', ',nullif(trim(co.address),''),nullif(trim(co.number),''));company_addr=concat_ws(' - ',nullif(company_addr,''),nullif(trim(co.neighborhood),''),nullif(concat_ws('/',nullif(trim(co.city),''),nullif(trim(co.state),'')),''));
 insert into receipts(company_id,service_id,payment_id,client_id,amount,payment_method,paid_at,created_by,service_number,client_name,client_document,client_phone,work_address,company_name,company_document,company_address,company_phone,company_whatsapp,company_logo_url,payment_notes,created_by_name,service_total,received_through_payment,remaining_balance,settlement_status)
 values(p.company_id,s.id,p.id,c.id,p.amount,p.payment_method,p.paid_at,p.created_by,s.service_number,c.name,c.document,c.phone,coalesce(nullif(work,''),'Não informado'),co.name,co.document,company_addr,co.phone,co.whatsapp,co.logo_url,p.notes,creator_name,s.amount,received,balance,case when balance=0 then 'paid' else 'partial' end)
 on conflict(payment_id) do nothing returning * into result;
 if result.id is null then select * into result from receipts where payment_id=target_payment_id;end if;return result;
end$$;
grant execute on function public.generate_receipt(uuid) to authenticated;