-- Dados exclusivamente locais. UUIDs e e-mails DEV permitem reset idempotente.
-- Senha de ambas as contas: DevLocal#2026
do $$
declare
  v_company_id uuid := '10000000-0000-4000-8000-000000000001';
  admin_id uuid := '10000000-0000-4000-8000-000000000002';
  employee_id uuid := '10000000-0000-4000-8000-000000000003';
  client_one uuid := '10000000-0000-4000-8000-000000000011';
  client_two uuid := '10000000-0000-4000-8000-000000000012';
  client_three uuid := '10000000-0000-4000-8000-000000000013';
  address_one uuid := '10000000-0000-4000-8000-000000000021';
  address_two uuid := '10000000-0000-4000-8000-000000000022';
  address_three uuid := '10000000-0000-4000-8000-000000000023';
  service_one uuid := '10000000-0000-4000-8000-000000000031';
  service_two uuid := '10000000-0000-4000-8000-000000000032';
  service_three uuid := '10000000-0000-4000-8000-000000000033';
  service_four uuid := '10000000-0000-4000-8000-000000000034';
begin
  insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change)
  values
   ('00000000-0000-0000-0000-000000000000',admin_id,'authenticated','authenticated','admin@teste.local',crypt('DevLocal#2026',gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}','{"full_name":"Administrador DEV"}',now(),now(),'','','',''),
   ('00000000-0000-0000-0000-000000000000',employee_id,'authenticated','authenticated','funcionario@teste.local',crypt('DevLocal#2026',gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}','{"full_name":"Funcionário DEV"}',now(),now(),'','','','')
  on conflict(id) do nothing;

  insert into auth.identities(id,user_id,provider_id,identity_data,provider,last_sign_in_at,created_at,updated_at)
  values
   (admin_id,admin_id,'admin@teste.local',jsonb_build_object('sub',admin_id::text,'email','admin@teste.local'),'email',now(),now(),now()),
   (employee_id,employee_id,'funcionario@teste.local',jsonb_build_object('sub',employee_id::text,'email','funcionario@teste.local'),'email',now(),now(),now())
  on conflict(provider_id,provider) do nothing;

  insert into public.companies(id,name,document,address,number,neighborhood,city,state,zip_code,phone,whatsapp,email)
  values(v_company_id,'Nova Tira Entulho — DEV','00.000.000/0000-00','Avenida de Testes','100','Bairro Fictício','São Paulo','SP','00000-000','(11) 3000-0000','(11) 90000-0000','dev@teste.local')
  on conflict(id) do nothing;

  insert into public.profiles(id,company_id,full_name,role,is_active,is_support)
  values(admin_id,v_company_id,'Administrador DEV','admin',true,false),(employee_id,v_company_id,'Funcionário DEV','employee',true,false)
  on conflict(id) do nothing;

  insert into public.settings(company_id,key,value) values(v_company_id,'total_dumpsters','80'::jsonb),(v_company_id,'low_dumpster_threshold','10'::jsonb)
  on conflict(company_id,key) do update set value=excluded.value;

  insert into public.clients(id,company_id,name,document,phone,email,address,city,notes,created_by,demo_batch)
  values
   (client_one,v_company_id,'Cliente Teste Alfa','111.111.111-11','(11) 90000-1001','alfa@teste.local','Rua Alfa','São Paulo','Registro fictício local',admin_id,'LOCAL_DEV'),
   (client_two,v_company_id,'Construtora Exemplo DEV','00.111.222/0001-33','(11) 90000-1002','obras@teste.local','Avenida Beta','São Paulo','Registro fictício local',admin_id,'LOCAL_DEV'),
   (client_three,v_company_id,'Reformas Modelo','222.222.222-22','(11) 90000-1003','modelo@teste.local','Rua Gama','Guarulhos','Registro fictício local',admin_id,'LOCAL_DEV')
  on conflict(id) do nothing;

  insert into public.client_addresses(id,company_id,client_id,address,number,neighborhood,city,state,zip_code,notes)
  values
   (address_one,v_company_id,client_one,'Rua das Acácias','101','Centro','São Paulo','SP','00000-101','Obra fictícia'),
   (address_two,v_company_id,client_two,'Avenida dos Projetos','202','Industrial','São Paulo','SP','00000-202','Obra fictícia'),
   (address_three,v_company_id,client_three,'Rua do Modelo','303','Jardim DEV','Guarulhos','SP','00000-303','Obra fictícia')
  on conflict(id) do nothing;

  insert into public.services(id,company_id,client_id,address_id,quantity,scheduled_delivery_date,status,amount,payment_method,payment_status,notes,created_by,demo_batch)
  values
   (service_one,v_company_id,client_one,address_one,1,current_date+1,'scheduled',420,'Pix','pending','OS local agendada',admin_id,'LOCAL_DEV'),
   (service_two,v_company_id,client_two,address_two,1,current_date-2,'scheduled',500,'Transferência','pending','OS local entregue',admin_id,'LOCAL_DEV'),
   (service_three,v_company_id,client_three,address_three,1,current_date-7,'scheduled',450,'Dinheiro','pending','OS local aguardando retirada',admin_id,'LOCAL_DEV'),
   (service_four,v_company_id,client_one,address_one,1,current_date-10,'scheduled',350,'Pix','pending','OS local concluída',admin_id,'LOCAL_DEV')
  on conflict(id) do nothing;

  update public.service_dumpsters set status='delivered',delivered_at=now()-interval '2 days',deadline_at=now()+interval '5 days'
   where service_id=service_two;
  update public.service_dumpsters set status='waiting_collection',delivered_at=now()-interval '7 days',deadline_at=now(),collection_requested_at=now()-interval '2 hours'
   where service_id=service_three;
  update public.service_dumpsters set status='collected',delivered_at=now()-interval '10 days',deadline_at=now()-interval '3 days',collected_at=now()-interval '3 days'
   where service_id=service_four;
  insert into public.service_payments(company_id,service_id,amount,payment_method,paid_at,notes,created_by)
  values(v_company_id,service_four,350,'Pix',now()-interval '9 days','Pagamento fictício local',admin_id)
  on conflict do nothing;
end $$;
