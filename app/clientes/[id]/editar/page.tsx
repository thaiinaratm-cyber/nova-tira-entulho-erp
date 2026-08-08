import {notFound,redirect} from "next/navigation";
import {AppShell} from "@/components/shell";
import {ClientEditForm} from "@/components/client-edit-form";
import {ClientArchiveAction} from "@/components/client-archive-actions";
import {createSupabaseServerClient} from "@/lib/supabase/server";

export const dynamic="force-dynamic";
export default async function EditarCliente({params}:{params:Promise<{id:string}>}){
 const{id}=await params;const sb=await createSupabaseServerClient();const{data:{user}}=await sb.auth.getUser();if(!user)redirect("/login");
 const[{data,error},{data:profile}]=await Promise.all([sb.from("clients").select("id,name,phone,document,email,address,city,notes,archived_at").eq("id",id).single(),sb.from("profiles").select("role").eq("id",user.id).single()]);
 if(error){if(error.code==="PGRST116")notFound();throw new Error("Não foi possível carregar o cliente.")}
 if(data.archived_at)redirect("/arquivados");
 return <AppShell title="Clientes / Editar"><div className="heading"><div><h1>Editar cliente</h1><div className="sub">O histórico de serviços não será alterado.</div></div>{profile?.role==="admin"&&<ClientArchiveAction clientId={id}/>}</div><ClientEditForm client={data}/></AppShell>;
}
