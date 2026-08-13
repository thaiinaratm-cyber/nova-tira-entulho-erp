-- Configuração inicial de estoque da empresa atual.
insert into public.settings(company_id,key,value)
select company_id,'total_dumpsters','80'::jsonb
from public.profiles
where role='admin'
order by created_at
limit 1
on conflict(company_id,key) do update set value='80'::jsonb,updated_at=now();
