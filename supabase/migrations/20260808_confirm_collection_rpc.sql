-- RPC de retirada da OS. Idempotente e compatível com a chamada do frontend.
create or replace function public.confirm_collection(service_id uuid)
returns public.services
language plpgsql
security definer
set search_path = public
as $$
declare
  authenticated_company_id uuid;
  service_company_id uuid;
  current_status public.service_status;
  result public.services;
begin
  authenticated_company_id := public.current_company_id();

  if authenticated_company_id is null then
    raise exception using
      errcode = 'P0001',
      message = 'Usuário autenticado não está associado a uma empresa.';
  end if;

  select s.company_id, s.status
    into service_company_id, current_status
    from public.services s
   where s.id = service_id;

  if not found then
    raise exception using
      errcode = 'P0001',
      message = 'Serviço não encontrado.';
  end if;

  if service_company_id <> authenticated_company_id then
    raise exception using
      errcode = 'P0001',
      message = 'O serviço não pertence à empresa do usuário autenticado.';
  end if;

  if current_status <> 'waiting_collection' then
    raise exception using
      errcode = 'P0001',
      message = 'A retirada só pode ser confirmada para serviço aguardando retirada.';
  end if;

  update public.services
     set collected_at = now(),
         status = 'completed'
   where id = service_id
     and company_id = authenticated_company_id
     and status = 'waiting_collection'
  returning * into result;

  if result.id is null then
    raise exception using
      errcode = 'P0001',
      message = 'A retirada não pôde ser confirmada porque o serviço foi alterado por outra operação.';
  end if;

  return result;
end;
$$;

revoke all on function public.confirm_collection(uuid) from public;
grant execute on function public.confirm_collection(uuid) to authenticated;

-- Solicita ao PostgREST/Supabase a atualização imediata do schema cache.
notify pgrst, 'reload schema';
