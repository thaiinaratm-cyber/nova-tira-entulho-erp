"use client";
import Link from "next/link";
import {useState} from "react";
import {useRouter} from "next/navigation";
import {FileDown} from "lucide-react";
import {createSupabaseBrowserClient} from "@/lib/supabase/client";
import type {ServiceStatus} from "@/lib/erp";

export function ServiceActions({id,status,compact=false}:{id:string;status:ServiceStatus;compact?:boolean}){
 const router=useRouter();const[busy,setBusy]=useState(false);const[error,setError]=useState("");
 async function run(action:"deliver"|"waiting_collection"|"completed"|"cancel"){
  if(action==="cancel"&&!window.confirm("Cancelar esta OS agendada? A reserva será liberada e a OS permanecerá no histórico."))return;
  setBusy(true);setError("");const supabase=createSupabaseBrowserClient();const rpc=action==="deliver"?"confirm_delivery":action==="waiting_collection"?"request_collection":action==="completed"?"confirm_collection":"cancel_scheduled_service";const result=await supabase.rpc(rpc,{service_id:id});
  if(result.error){console.error("[serviços/detalhe] Falha na operação",result.error);setError(result.error.message)}else router.refresh();setBusy(false);
 }
 const className=compact?"btn operationButton":"btn";
 return <div className={compact?"quickActions":"serviceActionBar"}>{!compact&&<><a className="btn secondary serviceOrderButton" href={`/api/servicos/${id}/pdf`} download><FileDown size={16}/> Gerar Ordem de Serviço</a><Link className="btn secondary" href={`/servicos/${id}/editar`}>Editar serviço</Link></>}{status==="scheduled"&&<button title="Confirmar entrega" className={className} disabled={busy} onClick={()=>run("deliver")}>Confirmar entrega</button>}{status==="delivered"&&<button title="Marcar para retirada" className={className} disabled={busy} onClick={()=>run("waiting_collection")}>Marcar para retirada</button>}{status==="waiting_collection"&&<button title="Confirmar retirada" className={className} disabled={busy} onClick={()=>run("completed")}>Confirmar retirada</button>}{status==="scheduled"&&!compact&&<button className="btn cancelButton" disabled={busy} onClick={()=>run("cancel")}>Cancelar serviço</button>}{error&&<p className="deadline overdue">{error}</p>}</div>;
}
