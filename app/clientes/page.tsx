import Link from "next/link";
import {redirect} from "next/navigation";
import {AppShell} from "@/components/shell";
import {ClientList} from "./client-list";
import {createSupabaseServerClient} from "@/lib/supabase/server";

type ServiceSummary={amount:number|string|null;status:string;service_payments:{amount:number|string}[]};
export const dynamic="force-dynamic";

export default async function Clientes(){
 const supabase=await createSupabaseServerClient();const{data:{user}}=await supabase.auth.getUser();if(!user)redirect("/login");
 const{data,error}=await supabase.from("clients").select("id,name,document,phone,city,services(amount,status,service_payments(amount))").is("archived_at",null).order("name",{ascending:true});
 if(error){console.error("[clientes] Falha ao buscar clientes",error);throw new Error(`Não foi possível carregar os clientes: ${error.message}`)}
 const clients=(data||[]).map(client=>{const services=(client.services||[]) as unknown as ServiceSummary[];const valid=services.filter(s=>s.status!=="cancelled");return{id:client.id,name:client.name,document:client.document,phone:client.phone,city:client.city,serviceCount:services.length,totalSpent:services.filter(s=>s.status==="completed").reduce((sum,s)=>sum+Number(s.amount||0),0),pendingAmount:valid.reduce((sum,s)=>{const received=(s.service_payments||[]).reduce((n,p)=>n+Number(p.amount),0);return sum+Math.max(0,Number(s.amount||0)-received)},0)}});
 return <AppShell title="Clientes"><div className="heading"><div><h1>Clientes</h1><div className="sub">Cadastros, endereços e histórico de serviços.</div></div><Link className="btn" href="/clientes/novo">+ Novo cliente</Link></div><ClientList clients={clients}/></AppShell>;
}
