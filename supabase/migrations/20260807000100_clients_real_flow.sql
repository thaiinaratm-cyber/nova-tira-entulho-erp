-- Confirmação idempotente das permissões do fluxo real de clientes.
grant execute on function public.current_company_id() to authenticated;

drop policy if exists clients_company on public.clients;
drop policy if exists clients_company_select on public.clients;
drop policy if exists clients_company_insert on public.clients;
drop policy if exists clients_company_update on public.clients;
drop policy if exists clients_company_delete on public.clients;

create policy clients_company_select on public.clients for select to authenticated
using (company_id = public.current_company_id());

create policy clients_company_insert on public.clients for insert to authenticated
with check (company_id = public.current_company_id());

create policy clients_company_update on public.clients for update to authenticated
using (company_id = public.current_company_id())
with check (company_id = public.current_company_id());

create policy clients_company_delete on public.clients for delete to authenticated
using (company_id = public.current_company_id());

-- Diagnóstico manual esperado para o usuário informado:
-- select public.current_company_id();
-- Resultado esperado: b392cf5a-f6b2-4944-befa-b38b763b2c6f
