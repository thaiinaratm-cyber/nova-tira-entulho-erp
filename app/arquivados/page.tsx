import {redirect} from "next/navigation";
import {AppShell} from "@/components/shell";
import {ClientArchiveAction} from "@/components/client-archive-actions";
import {requireAdminAccess} from "@/lib/auth";

export const dynamic="force-dynamic";
export default async function Arquivados(){
 const access=await requireAdminAccess();if(!access.ok)redirect(access.status===401?"/login":"/dashboard");
 const{data,error}=await access.supabase.from("clients").select("id,name,document,phone,city,archived_at").not("archived_at","is",null).order("archived_at",{ascending:false});
 if(error){console.error("[arquivados] Clientes",error);throw new Error("Não foi possível carregar os clientes arquivados.")}
 return <AppShell title="Administração / Arquivados"><div className="heading"><div><h1>Arquivados</h1><div className="sub">Registros retirados das listagens operacionais, com histórico preservado.</div></div></div><section className="section"><div className="sectionTitle"><h2>Clientes arquivados</h2></div>{!data?.length?<div className="card emptyState">Nenhum cliente arquivado.</div>:<div className="tableWrap"><table><thead><tr><th>Cliente</th><th>Telefone</th><th>Cidade</th><th>Arquivado em</th><th>Ações</th></tr></thead><tbody>{data.map(client=><tr key={client.id}><td><b>{client.name}</b><div className="sub">{client.document||"Sem documento"}</div></td><td>{client.phone}</td><td>{client.city||"—"}</td><td>{new Date(client.archived_at!).toLocaleString("pt-BR")}</td><td><ClientArchiveAction clientId={client.id} mode="restore"/></td></tr>)}</tbody></table></div>}</section></AppShell>;
}
