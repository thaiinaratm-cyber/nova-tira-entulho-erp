import {redirect} from "next/navigation";
import {createSupabaseServerClient} from "@/lib/supabase/server";
import {NewServiceForm} from "./service-form";

export const dynamic="force-dynamic";
export default async function NovoServico(){
 const sb=await createSupabaseServerClient();const{data:{user}}=await sb.auth.getUser();if(!user)redirect("/login");
 const{data,error}=await sb.from("clients").select("id,name,client_addresses(id,address,number,city)").is("archived_at",null).order("name");
 if(error){console.error("[servicos/novo] Clientes",error);throw new Error("Não foi possível carregar os clientes.")}
 return <NewServiceForm clients={(data||[]) as unknown as Parameters<typeof NewServiceForm>[0]["clients"]}/>;
}
