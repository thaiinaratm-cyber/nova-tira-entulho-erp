-- Personalização da empresa · Nova Tira Entulho
alter table public.companies
  add column if not exists document text,
  add column if not exists address text,
  add column if not exists number text,
  add column if not exists neighborhood text,
  add column if not exists city text,
  add column if not exists state char(2),
  add column if not exists zip_code text,
  add column if not exists phone text,
  add column if not exists whatsapp text,
  add column if not exists email text,
  add column if not exists logo_url text,
  add column if not exists updated_at timestamptz not null default now();

update public.companies
set name='Nova Tira Entulho',
    document='12.566.272/0001-32',
    address='Avenida Mário Covas Júnior',
    number='2222',
    neighborhood='Bairro do Portão',
    phone='4653-3261',
    whatsapp='(11) 94569-0387',
    updated_at=now()
where id = (
  select company_id from public.profiles
  where role = 'admin'
  order by created_at
  limit 1
);

create index if not exists companies_document_idx on public.companies(document);

drop policy if exists companies_admin_update on public.companies;
create policy companies_admin_update on public.companies
for update to authenticated
using (
  id=public.current_company_id()
  and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')
)
with check (
  id=public.current_company_id()
  and exists(select 1 from public.profiles p where p.id=auth.uid() and p.role='admin')
);

drop trigger if exists companies_updated on public.companies;
create trigger companies_updated before update on public.companies
for each row execute function public.set_updated_at();
