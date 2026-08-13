import Link from "next/link";
import {notFound,redirect} from "next/navigation";
import {FileDown} from "lucide-react";
import {AppShell} from "@/components/shell";
import {ServiceDumpsters,type DumpsterRow} from "@/components/service-dumpsters";
import {PaymentRegistration} from "@/components/payment-registration";
import {PaymentDetailsButton,ReceiptActionButton} from "@/components/view-actions";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {money,labels,paymentLabels,ServiceStatus,PaymentStatus} from "@/lib/erp";
import {formatDateTime} from "@/lib/date-time.mjs";

type Payment={id:string;amount:number|string;payment_method:string;paid_at:string;notes:string|null;created_by_name:string|null;receipts:{id:string}[]};
type Row={id:string;service_number:string;quantity:number;status:ServiceStatus;amount:number|string;payment_status:PaymentStatus;notes:string|null;clients:{name:string;phone:string}|null;client_addresses:{address:string;number:string|null;neighborhood:string|null;city:string;state:string}|null;service_payments:Payment[];service_dumpsters:DumpsterRow[]};
type AuditEvent={id:string;dumpster_id:string|null;event_type:"dumpster_cancelled"|"delivery_reversed"|"service_cancelled";previous_status:string;new_status:string;reason:string|null;performed_by_name:string|null;occurred_at:string};
const auditLabels={dumpster_cancelled:"Caçamba cancelada",delivery_reversed:"Entrega desfeita",service_cancelled:"OS cancelada"};
const unitLabels={scheduled:"Agendada",delivered:"Entregue",waiting_collection:"Aguardando retirada",collected:"Retirada",cancelled:"Cancelada",completed:"Finalizada"};
export const dynamic="force-dynamic";

export default async function Detalhe({params}:{params:Promise<{id:string}>}){
 const{id}=await params;const sb=await createSupabaseServerClient();const{data:{user}}=await sb.auth.getUser();if(!user)redirect("/login");
 const[serviceResult,profileResult,auditResult]=await Promise.all([
  sb.from("services").select("id,service_number,quantity,status,amount,payment_status,notes,clients(name,phone),client_addresses(address,number,neighborhood,city,state),service_payments(id,amount,payment_method,paid_at,notes,created_by_name,receipts(id)),service_dumpsters(id,delivery_scheduled_at,delivered_at,deadline_at,collection_requested_at,collected_at,status,value,notes)").eq("id",id).order("paid_at",{referencedTable:"service_payments",ascending:false}).order("created_at",{referencedTable:"service_dumpsters",ascending:true}).single(),
  sb.from("profiles").select("role").eq("id",user.id).single(),
  sb.from("service_dumpster_events").select("id,dumpster_id,event_type,previous_status,new_status,reason,performed_by_name,occurred_at").eq("service_id",id).order("occurred_at",{ascending:false})
 ]);
 if(serviceResult.error){if(serviceResult.error.code==="PGRST116")notFound();console.error("[serviços/detalhe] Consulta",serviceResult.error);throw new Error("Não foi possível carregar a OS.")}
 if(profileResult.error)console.error("[serviços/detalhe] Perfil",profileResult.error);
 if(auditResult.error)console.error("[serviços/detalhe] Auditoria",auditResult.error);
 const service=serviceResult.data as unknown as Row;const payments=service.service_payments||[];const dumpsters=service.service_dumpsters||[];const events=(auditResult.data||[]) as AuditEvent[];const isAdmin=profileResult.data?.role==="admin";const isCancelled=service.status==="cancelled";
 const received=payments.reduce((sum,payment)=>sum+Number(payment.amount),0);const balance=Math.max(0,Number(service.amount)-received);const clientName=service.clients?.name||"Cliente";const address=service.client_addresses?`${service.client_addresses.address}${service.client_addresses.number?`, ${service.client_addresses.number}`:""} · ${service.client_addresses.neighborhood?`${service.client_addresses.neighborhood} · `:""}${service.client_addresses.city}/${service.client_addresses.state}`:"—";
 const unitNumber=new Map(dumpsters.map((item,index)=>[item.id,index+1]));
 return <AppShell title={`Serviços / ${service.service_number}`}>
  <div className="heading"><div><h1>{service.service_number}</h1><div className="sub">Ordem de serviço de {clientName} · {dumpsters.filter(item=>item.status!=="cancelled").length} caçamba{dumpsters.filter(item=>item.status!=="cancelled").length===1?"":"s"}</div></div><span className={`status ${service.status}`}>{labels[service.status]}</span></div>
  <div className="serviceTopActions"><a className="btn secondary serviceOrderButton" href={`/api/servicos/${id}/pdf`} download><FileDown size={16}/> Gerar Ordem de Serviço</a>{!isCancelled&&<Link className="btn secondary" href={`/servicos/${id}/editar`}>Editar serviço</Link>}</div>
  {isCancelled&&<div className="notice cancelledNotice">Esta OS está cancelada. Os dados operacionais, pagamentos, recibos e o histórico permanecem disponíveis somente para consulta.</div>}
  <div className="grid"><div className="card wide"><h2>{clientName}</h2><p>{service.clients?.phone||"—"}</p><p>{address}</p></div><div className={`card financeCard ${balance>0?"hasBalance":"isPaid"}`}><div className="financeCardHeader"><div><span className="eyebrow">Financeiro</span><h2>Resumo do pagamento</h2></div><span className={`status ${balance===0?"paid":service.payment_status}`}>{balance===0?"Pago":paymentLabels[service.payment_status]}</span></div><div className="financeRows"><div><span>Valor total</span><strong>{money(service.amount)}</strong></div><div><span>Recebido</span><strong className="receivedValue">{money(received)}</strong></div><div className="balanceRow"><span>Saldo a receber</span><strong>{money(balance)}</strong></div></div>{!isCancelled&&<div className="financeAction"><PaymentRegistration serviceId={service.id} balance={balance}/>{balance===0&&<span className="paidMessage">Pagamento integral recebido</span>}</div>}</div></div>
  {service.notes&&<section className="section card"><h2>Observações da OS</h2><p>{service.notes}</p></section>}
  <ServiceDumpsters serviceId={service.id} dumpsters={dumpsters} isAdmin={isAdmin} serviceStatus={service.status}/>
  <section className="section"><div className="sectionTitle"><h2>Histórico operacional</h2></div>{events.length===0?<div className="card emptyState">Nenhuma correção operacional registrada.</div>:<div className="auditList">{events.map(event=><article className="card auditEvent" key={event.id}><div><strong>{auditLabels[event.event_type]}</strong>{event.dumpster_id&&<span>Caçamba {unitNumber.get(event.dumpster_id)||"—"}</span>}</div><p>{unitLabels[event.previous_status as keyof typeof unitLabels]||event.previous_status} → {unitLabels[event.new_status as keyof typeof unitLabels]||event.new_status}</p><p>{event.reason||"Motivo não informado"}</p><small>{formatDateTime(event.occurred_at)} · {event.performed_by_name||"Usuário não identificado"}</small></article>)}</div>}</section>
  <section className="section"><div className="sectionTitle"><h2>Pagamentos</h2></div>{payments.length===0?<div className="card emptyState">Nenhum pagamento registrado.</div>:<div className="tableWrap paymentsTable"><table><thead><tr><th>Data</th><th>Valor</th><th>Forma</th><th>Observação</th><th>Registrado por</th><th>Ações</th></tr></thead><tbody>{payments.map(payment=>{const userName=payment.created_by_name||"Sistema";const receiptId=payment.receipts?.[0]?.id||null;return <tr key={payment.id}><td>{formatDateTime(payment.paid_at)}</td><td><b>{money(payment.amount)}</b></td><td>{payment.payment_method}</td><td>{payment.notes||"—"}</td><td>{userName}</td><td><div className="actionGroup"><PaymentDetailsButton payment={{id:payment.id,receiptId,amount:payment.amount,paidAt:payment.paid_at,method:payment.payment_method,notes:payment.notes,userName,serviceNumber:service.service_number,clientName}}/><ReceiptActionButton paymentId={payment.id} initialReceiptId={receiptId}/></div></td></tr>})}</tbody></table></div>}</section>
 </AppShell>;
}
