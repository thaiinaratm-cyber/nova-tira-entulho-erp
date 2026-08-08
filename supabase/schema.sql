-- Sprint 1 · Pátio ERP
create extension if not exists pgcrypto;
create type public.user_role as enum ('admin','employee');
create type public.service_status as enum ('scheduled','delivered','waiting_collection','completed','cancelled');
create type public.payment_status as enum ('pending','paid');

create table public.companies(id uuid primary key default gen_random_uuid(),name text not null,document text,address text,number text,neighborhood text,city text,state char(2),zip_code text,phone text,whatsapp text,email text,logo_url text,created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.profiles(id uuid primary key references auth.users(id) on delete cascade,company_id uuid not null references public.companies(id),full_name text not null,role public.user_role not null default 'employee',created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table public.clients(id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),name text not null,document text,phone text not null,email text,address text,city text,notes text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),constraint clients_phone_company_unique unique(company_id,phone));
create table public.client_addresses(id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),client_id uuid not null references public.clients(id) on delete cascade,address text not null,number text,complement text,neighborhood text,city text not null,state char(2) not null,zip_code text,notes text,created_at timestamptz not null default now());
create sequence public.service_number_seq start 1;
create table public.services(id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),service_number text not null unique default ('OS-'||lpad(nextval('public.service_number_seq')::text,6,'0')),client_id uuid not null references public.clients(id),address_id uuid not null references public.client_addresses(id),quantity integer not null check(quantity>0),scheduled_delivery_date date not null,delivered_at timestamptz,deadline_date date,collected_at timestamptz,status public.service_status not null default 'scheduled',amount numeric(12,2) not null default 0 check(amount>=0),payment_method text not null check(payment_method in ('Pix','Dinheiro','Cartão','Transferência','Boleto','Outro')),payment_status public.payment_status not null default 'pending',notes text,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),constraint service_delivery_consistency check((delivered_at is null and deadline_date is null) or delivered_at is not null));
create table public.settings(id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),key text not null,value jsonb not null,created_at timestamptz not null default now(),updated_at timestamptz not null default now(),unique(company_id,key));
-- Extensões futuras preservam o prazo original e registram cada alteração.
create table public.service_extensions(id uuid primary key default gen_random_uuid(),company_id uuid not null references public.companies(id),service_id uuid not null references public.services(id) on delete cascade,additional_days integer not null check(additional_days>0),reason text not null,previous_deadline date not null,new_deadline date not null,created_by uuid references public.profiles(id),created_at timestamptz not null default now());

create index clients_company_name_idx on public.clients(company_id,name);
create index clients_search_idx on public.clients(company_id,phone,document);
create index addresses_client_idx on public.client_addresses(client_id);
create index services_company_status_idx on public.services(company_id,status);
create index services_client_idx on public.services(client_id,created_at desc);
create index services_deadline_idx on public.services(company_id,deadline_date) where status in ('delivered','waiting_collection');

create function public.set_updated_at() returns trigger language plpgsql as $$begin new.updated_at=now();return new;end$$;
create trigger companies_updated before update on public.companies for each row execute function public.set_updated_at();
create trigger profiles_updated before update on public.profiles for each row execute function public.set_updated_at();
create trigger clients_updated before update on public.clients for each row execute function public.set_updated_at();
create trigger services_updated before update on public.services for each row execute function public.set_updated_at();
create trigger settings_updated before update on public.settings for each row execute function public.set_updated_at();

create function public.current_company_id() returns uuid language sql stable security definer set search_path=public set row_security=off as $$select company_id from public.profiles where id=auth.uid()$$;
create function public.current_user_is_admin() returns boolean language sql stable security definer set search_path=public set row_security=off as $$select coalesce((select role='admin' from public.profiles where id=auth.uid()),false)$$;
create function public.confirm_delivery(service_id uuid) returns public.services language plpgsql security definer set search_path=public as $$declare result public.services;begin update services set delivered_at=now(),deadline_date=(now()+interval '7 days')::date,status='delivered' where id=service_id and company_id=current_company_id() and status='scheduled' returning * into result;if result.id is null then raise exception 'Serviço inválido ou já entregue';end if;return result;end$$;
create function public.confirm_collection(service_id uuid) returns public.services language plpgsql security definer set search_path=public as $$declare result public.services;begin update services set collected_at=now(),status='completed' where id=service_id and company_id=current_company_id() and status='waiting_collection' and delivered_at is not null returning * into result;if result.id is null then raise exception 'Serviço inválido ou não está aguardando retirada';end if;return result;end$$;
create function public.available_dumpsters(requested_company uuid) returns integer language sql stable security definer set search_path=public as $$select greatest(0,coalesce((select (value#>>'{}')::int from settings where company_id=requested_company and key='total_dumpsters'),0)-coalesce((select sum(quantity) from services where company_id=requested_company and status in ('scheduled','delivered','waiting_collection')),0))$$;
create function public.prevent_negative_inventory() returns trigger language plpgsql security definer set search_path=public as $$declare total int;used int;begin if new.status in ('scheduled','delivered','waiting_collection') then select coalesce((value#>>'{}')::int,0) into total from settings where company_id=new.company_id and key='total_dumpsters';select coalesce(sum(quantity),0) into used from services where company_id=new.company_id and status in ('scheduled','delivered','waiting_collection') and id<>new.id;if used+new.quantity>total then raise exception 'Quantidade de caçambas indisponível';end if;end if;return new;end$$;
create trigger services_inventory_guard before insert or update on public.services for each row execute function public.prevent_negative_inventory();

alter table public.companies enable row level security;alter table public.profiles enable row level security;alter table public.clients enable row level security;alter table public.client_addresses enable row level security;alter table public.services enable row level security;alter table public.settings enable row level security;alter table public.service_extensions enable row level security;
create policy companies_member on public.companies for select to authenticated using(id=current_company_id());
create policy companies_admin_update on public.companies for update to authenticated using(id=current_company_id() and exists(select 1 from profiles p where p.id=auth.uid() and p.role='admin')) with check(id=current_company_id());
create policy profiles_self_select on public.profiles for select to authenticated using(id=auth.uid());
create policy profiles_company_select on public.profiles for select to authenticated using(current_user_is_admin() and company_id=current_company_id());
create policy profiles_admin_insert on public.profiles for insert to authenticated with check(current_user_is_admin() and company_id=current_company_id());
create policy profiles_admin_update on public.profiles for update to authenticated using(current_user_is_admin() and company_id=current_company_id()) with check(current_user_is_admin() and company_id=current_company_id());
create policy profiles_admin_delete on public.profiles for delete to authenticated using(current_user_is_admin() and company_id=current_company_id() and id<>auth.uid());
create policy clients_company_select on public.clients for select to authenticated using(company_id=current_company_id());
create policy clients_company_insert on public.clients for insert to authenticated with check(company_id=current_company_id());
create policy clients_company_update on public.clients for update to authenticated using(company_id=current_company_id()) with check(company_id=current_company_id());
create policy clients_company_delete on public.clients for delete to authenticated using(company_id=current_company_id());
create policy addresses_company on public.client_addresses for all to authenticated using(company_id=current_company_id()) with check(company_id=current_company_id());
create policy services_company on public.services for all to authenticated using(company_id=current_company_id()) with check(company_id=current_company_id());
create policy settings_read on public.settings for select to authenticated using(company_id=current_company_id());
create policy settings_admin on public.settings for all to authenticated using(company_id=current_company_id() and exists(select 1 from profiles p where p.id=auth.uid() and p.role='admin')) with check(company_id=current_company_id());
create policy extensions_company on public.service_extensions for all to authenticated using(company_id=current_company_id()) with check(company_id=current_company_id());
grant execute on function public.current_company_id() to authenticated;grant execute on function public.current_user_is_admin() to authenticated;grant execute on function public.confirm_delivery(uuid) to authenticated;grant execute on function public.confirm_collection(uuid) to authenticated;grant execute on function public.available_dumpsters(uuid) to authenticated;
-- Bootstrap: crie a empresa, depois o usuário no Auth e então o profile usando os UUIDs reais.
