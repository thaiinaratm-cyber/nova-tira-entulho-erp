"use client";
import {useMemo,useState} from "react";
import {useRouter} from "next/navigation";
import {X} from "lucide-react";
import {AppShell} from "@/components/shell";
import {createSupabaseBrowserClient} from "@/lib/supabase/client";
import {getAuthenticatedProfile} from "@/lib/supabase/profile";

type Address={id:string;address:string;number:string|null;city:string};
type Client={id:string;name:string;client_addresses:Address[]};

export function NewServiceForm({clients:initialClients}:{clients:Client[]}){
 const router=useRouter();
 const[clients,setClients]=useState(initialClients);
 const[clientId,setClientId]=useState("");
 const[addressId,setAddressId]=useState("");
 const[isNewAddress,setIsNewAddress]=useState(false);
 const[clientModal,setClientModal]=useState(false);
 const[error,setError]=useState("");
 const[modalError,setModalError]=useState("");
 const[saving,setSaving]=useState(false);
 const[savingClient,setSavingClient]=useState(false);
 const addresses=useMemo(()=>clients.find(c=>c.id===clientId)?.client_addresses||[],[clientId,clients]);

 async function createClient(event:React.FormEvent<HTMLFormElement>){
  event.preventDefault();setSavingClient(true);setModalError("");
  const form=new FormData(event.currentTarget);const sb=createSupabaseBrowserClient();
  const result=await getAuthenticatedProfile(sb);
  if(!result.ok){console.error("[servicos/novo/cliente] Profile",result);setModalError(result.message);setSavingClient(false);return}
  const payload={company_id:result.profile.company_id,name:String(form.get("client_name")).trim(),phone:String(form.get("client_phone")).trim(),document:String(form.get("client_document")||"").trim()||null,email:String(form.get("client_email")||"").trim()||null,city:String(form.get("client_city")||"").trim()||null,address:null,notes:null};
  const{data,error:insertError}=await sb.from("clients").insert(payload).select("id,name").single();
  if(insertError||!data){console.error("[servicos/novo/cliente] INSERT public.clients",{error:insertError,payload,userId:result.user.id});setModalError(insertError?.code==="23505"?"Já existe um cliente cadastrado com este telefone.":insertError?.message||"Não foi possível criar o cliente.");setSavingClient(false);return}
  const created:Client={id:data.id,name:data.name,client_addresses:[]};
  setClients(current=>[...current,created].sort((a,b)=>a.name.localeCompare(b.name,"pt-BR")));
  setClientId(created.id);setAddressId("");setIsNewAddress(true);setClientModal(false);setSavingClient(false);
 }

 async function submit(event:React.FormEvent<HTMLFormElement>){
  event.preventDefault();setSaving(true);setError("");const form=new FormData(event.currentTarget);const sb=createSupabaseBrowserClient();
  const result=await getAuthenticatedProfile(sb);
  if(!result.ok){console.error("[servicos/novo] Profile",result);setError(result.message);setSaving(false);return}
  const delivery=String(form.get("delivery"));const quantity=Number(form.get("quantity"));
  const{data:projected,error:projectionError}=await sb.rpc("projected_dumpster_availability",{target_date:delivery,exclude_service_id:null});
  if(projectionError){console.error("[servicos/novo] Disponibilidade projetada",projectionError);setError(`Não foi possível validar a disponibilidade futura: ${projectionError.message}`);setSaving(false);return}
  if(quantity>Number(projected||0)){setError(`Capacidade insuficiente em ${new Date(`${delivery}T12:00:00`).toLocaleDateString("pt-BR")}: ${quantity} caçambas solicitadas e ${Number(projected||0)} projetadas como disponíveis.`);setSaving(false);return}
  let finalAddressId=addressId;
  if(isNewAddress){
   const{data:address,error:addressError}=await sb.from("client_addresses").insert({company_id:result.profile.company_id,client_id:clientId,address:String(form.get("address")).trim(),number:String(form.get("number")||"").trim()||null,complement:String(form.get("complement")||"").trim()||null,neighborhood:String(form.get("neighborhood")||"").trim()||null,city:String(form.get("city")).trim(),state:String(form.get("state")).trim().toUpperCase(),zip_code:String(form.get("zip_code")||"").trim()||null}).select("id").single();
   if(addressError||!address){console.error("[servicos/novo] INSERT public.client_addresses",addressError);setError(addressError?.message||"Não foi possível salvar o endereço da obra.");setSaving(false);return}
   finalAddressId=address.id;
  }
  if(!finalAddressId){setError("Selecione ou cadastre um endereço para a obra.");setSaving(false);return}
  const payload={company_id:result.profile.company_id,client_id:clientId,address_id:finalAddressId,quantity,scheduled_delivery_date:delivery,amount:Number(form.get("amount")),payment_method:String(form.get("payment_method")),payment_status:"pending",notes:String(form.get("notes")||"").trim()||null,status:"scheduled"};
  const{data,error:insertError}=await sb.from("services").insert(payload).select("id").single();
  if(insertError||!data){console.error("[servicos/novo] INSERT public.services",{error:insertError,payload});setError(insertError?.message||"Não foi possível criar o serviço.");setSaving(false);return}
  router.push(`/servicos/${data.id}`);router.refresh();
 }

 return <AppShell title="Serviços / Novo">
  <div className="heading"><div><h1>Novo serviço</h1><div className="sub">A contagem de 7 dias só começa após confirmar a entrega.</div></div></div>
  <form className="card formGrid" onSubmit={submit}>
   {error&&<div className="notice formError full" role="alert">{error}</div>}
   <div className="field full"><div className="fieldHeading"><label htmlFor="service-client">Cliente *</label><button type="button" className="textButton" onClick={()=>{setModalError("");setClientModal(true)}}>+ Criar novo cliente</button></div><select id="service-client" required value={clientId} onChange={e=>{setClientId(e.target.value);setAddressId("");setIsNewAddress(false)}}><option value="" disabled>Selecione um cliente</option>{clients.map(c=><option key={c.id} value={c.id}>{c.name}</option>)}</select></div>
   <div className="field full"><label htmlFor="work-address">Endereço da obra *</label><select id="work-address" required={!isNewAddress} disabled={isNewAddress||!clientId} value={addressId} onChange={e=>setAddressId(e.target.value)}><option value="">Selecione um endereço já utilizado</option>{addresses.map(a=><option value={a.id} key={a.id}>{a.address}{a.number?`, ${a.number}`:""} · {a.city}</option>)}</select><button type="button" disabled={!clientId} className="btn secondary inlineAction" onClick={()=>{setIsNewAddress(!isNewAddress);setAddressId("")}}>{isNewAddress?"Usar endereço existente":"+ Cadastrar novo endereço da obra"}</button></div>
   {isNewAddress&&<><div className="field full"><label>Logradouro *</label><input name="address" required/></div><div className="field"><label>Número</label><input name="number"/></div><div className="field"><label>Complemento</label><input name="complement"/></div><div className="field"><label>Bairro</label><input name="neighborhood"/></div><div className="field"><label>Cidade *</label><input name="city" required/></div><div className="field"><label>Estado *</label><input name="state" required maxLength={2}/></div><div className="field"><label>CEP</label><input name="zip_code"/></div></>}
   <div className="field"><label>Quantidade *</label><input name="quantity" type="number" min="1" required defaultValue="1"/></div><div className="field"><label>Entrega prevista *</label><input name="delivery" type="date" required/></div><div className="field"><label>Valor *</label><input name="amount" type="number" min="0" step="0.01" required/></div><div className="field"><label>Forma de pagamento</label><select name="payment_method">{["Pix","Dinheiro","Cartão","Transferência","Boleto","Outro"].map(x=><option key={x}>{x}</option>)}</select></div><div className="field full"><label>Observações</label><textarea name="notes" rows={3}/></div><div className="full"><button className="btn" disabled={saving}>{saving?"Criando...":"Criar serviço"}</button> <button type="button" className="btn secondary" disabled={saving} onClick={()=>router.back()}>Cancelar</button></div>
  </form>
  {clientModal&&<div className="modalBackdrop" role="presentation" onMouseDown={e=>{if(e.target===e.currentTarget)setClientModal(false)}}><div className="modalCard" role="dialog" aria-modal="true" aria-labelledby="quick-client-title"><div className="modalHeader"><div><h2 id="quick-client-title">Criar novo cliente</h2><p className="sub">Somente nome e telefone são obrigatórios.</p></div><button type="button" className="iconButton" aria-label="Fechar" onClick={()=>setClientModal(false)}><X size={20}/></button></div><form className="formGrid" onSubmit={createClient}>{modalError&&<div className="notice formError full" role="alert">{modalError}</div>}<div className="field full"><label>Nome / Razão social *</label><input name="client_name" required autoFocus/></div><div className="field"><label>Telefone *</label><input name="client_phone" required/></div><div className="field"><label>CPF/CNPJ</label><input name="client_document"/></div><div className="field"><label>E-mail</label><input name="client_email" type="email"/></div><div className="field"><label>Cidade</label><input name="client_city"/></div><div className="full modalActions"><button type="button" className="btn secondary" onClick={()=>setClientModal(false)}>Cancelar</button><button className="btn" disabled={savingClient}>{savingClient?"Salvando...":"Salvar cliente"}</button></div></form></div></div>}
 </AppShell>;
}
