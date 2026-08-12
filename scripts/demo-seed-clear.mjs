import {DEMO_BATCH,assertCompany,context,fail} from "./demo-seed-data.mjs";
async function remove(sb,table,ids){if(!ids.length)return;const{error}=await sb.from(table).delete().in("id",ids);if(error)throw new Error(`${table}: ${error.message}`)}
async function run(){
 const{supabase,companyId}=context(),company=await assertCompany(supabase,companyId);const{data:services,error:serviceError}=await supabase.from("services").select("id").eq("company_id",companyId).eq("demo_batch",DEMO_BATCH);if(serviceError)throw new Error(`Execute a migration de identificação DEMO: ${serviceError.message}`);const{data:clients,error:clientError}=await supabase.from("clients").select("id").eq("company_id",companyId).eq("demo_batch",DEMO_BATCH);if(clientError)throw clientError;
 const serviceIds=(services||[]).map(x=>x.id),clientIds=(clients||[]).map(x=>x.id);if(!serviceIds.length&&!clientIds.length){console.log(`\n[DEMO] Nenhum registro ${DEMO_BATCH} encontrado em ${company.name}.`);return}
 if(serviceIds.length){const{data:receipts,error}=await supabase.from("receipts").select("id").in("service_id",serviceIds);if(error)throw error;await remove(supabase,"receipts",(receipts||[]).map(x=>x.id));const notification=await supabase.from("notifications").delete().eq("company_id",companyId).eq("related_type","service").in("related_id",serviceIds);if(notification.error)throw notification.error;const deleted=await supabase.from("services").delete().eq("company_id",companyId).eq("demo_batch",DEMO_BATCH);if(deleted.error)throw deleted.error}
 if(clientIds.length){const deleted=await supabase.from("clients").delete().eq("company_id",companyId).eq("demo_batch",DEMO_BATCH);if(deleted.error)throw deleted.error}
 console.log(`\n[DEMO] Limpeza concluída em ${company.name}.`);console.log(`- ${serviceIds.length} OS DEMO removidas`);console.log(`- ${clientIds.length} clientes DEMO removidos`);console.log("Nenhum registro fora do lote foi selecionado.");
}
run().catch(fail);
