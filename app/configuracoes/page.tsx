import {redirect} from "next/navigation";
import {AppShell} from "@/components/shell";
import {CompanySettingsForm} from "@/components/company-settings-form";
import {requireAdminAccess} from "@/lib/auth";
import {defaultCompany,type Company} from "@/lib/company";

export const dynamic="force-dynamic";
export default async function Configuracoes(){
 const access=await requireAdminAccess();if(!access.ok)redirect(access.status===401?"/login":"/dashboard");
 const[{data,error},{data:threshold,error:thresholdError}]=await Promise.all([access.supabase.from("companies").select("*").eq("id",access.profile.company_id).single(),access.supabase.from("settings").select("value").eq("company_id",access.profile.company_id).eq("key","low_dumpster_threshold").maybeSingle()]);
 if(error||thresholdError){console.error("[configurações]",{error,thresholdError});throw new Error("Não foi possível carregar as configurações da empresa.")}
 return <AppShell title="Configurações da Empresa"><CompanySettingsForm initialCompany={{...defaultCompany,...data} as Company} initialLowThreshold={Number(threshold?.value??10)}/></AppShell>;
}
