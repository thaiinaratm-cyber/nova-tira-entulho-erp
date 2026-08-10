import Link from "next/link";
import {redirect} from "next/navigation";
import {Boxes,Container,CalendarCheck,PackageCheck} from "lucide-react";
import {AppShell} from "@/components/shell";
import {createSupabaseServerClient} from "@/lib/supabase/server";
export const dynamic="force-dynamic";
export default async function Disponibilidade(){
 const sb=await createSupabaseServerClient();const{data:{user}}=await sb.auth.getUser();if(!user)redirect("/login");const{data:profile,error:profileError}=await sb.from("profiles").select("company_id").eq("id",user.id).single();if(profileError)throw new Error("Não foi possível identificar a empresa.");
 const[{data:setting,error:settingsError},{data:dumpsters,error:dumpstersError}]=await Promise.all([sb.from("settings").select("value").eq("company_id",profile.company_id).eq("key","total_dumpsters").single(),sb.from("service_dumpsters").select("status").in("status",["scheduled","delivered","waiting_collection"])]);
 if(settingsError){console.error("[disponibilidade] total_dumpsters",settingsError);throw new Error("Configure total_dumpsters nas configurações da empresa.")}if(dumpstersError){console.error("[disponibilidade] service_dumpsters",dumpstersError);throw new Error("Execute a migration de múltiplas caçambas no Supabase.")}
 const total=Number(setting.value||0),reserved=(dumpsters||[]).filter(item=>item.status==="scheduled").length,inClients=(dumpsters||[]).filter(item=>["delivered","waiting_collection"].includes(item.status)).length,available=Math.max(0,total-reserved-inClients);const cards=[{label:"Total",value:total,Icon:Boxes},{label:"Em clientes",value:inClients,Icon:Container},{label:"Reservadas",value:reserved,Icon:CalendarCheck},{label:"Disponíveis",value:available,Icon:PackageCheck}];
 return <AppShell title="Disponibilidade de caçambas"><div className="heading"><div><h1>Controle de disponibilidade</h1><div className="sub">Cada caçamba ativa compromete uma unidade do estoque.</div></div><Link className="btn secondary" href="/dashboard">← Voltar ao Dashboard</Link></div><div className="grid">{cards.map(({label,value,Icon})=><div className="card metric" key={label}><div><label>{label}</label><strong>{value}</strong></div><span className="metricIcon"><Icon size={20}/></span></div>)}</div><div className="card availabilityFormula"><b>Cálculo</b><span>{total} total − {inClients} em clientes − {reserved} reservadas = <strong>{available} disponíveis</strong></span></div></AppShell>;
}
