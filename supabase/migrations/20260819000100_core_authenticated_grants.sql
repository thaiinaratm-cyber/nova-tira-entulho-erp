-- Explicit privileges for the core tables created by the initial migration.
-- RLS policies remain responsible for company isolation.

grant select on public.companies to authenticated;

grant select,insert,update on public.clients to authenticated;
grant select,insert,update on public.client_addresses to authenticated;
grant select,insert,update on public.services to authenticated;
grant select,insert,update on public.settings to authenticated;
grant select,insert on public.service_extensions to authenticated;

grant usage,select on sequence public.service_number_seq to authenticated;

-- Operational records must continue using soft deletion/cancellation only.
revoke delete on public.clients from authenticated;
revoke delete on public.client_addresses from authenticated;
revoke delete on public.services from authenticated;

notify pgrst,'reload schema';
