"use client";
import {useState} from "react";
import {useRouter} from "next/navigation";
import {Archive,RotateCcw} from "lucide-react";
import {createSupabaseBrowserClient} from "@/lib/supabase/client";

export function ClientArchiveAction({clientId,mode="archive"}:{clientId:string;mode?:"archive"|"restore"}){
 const[busy,setBusy]=useState(false);const[error,setError]=useState("");const router=useRouter();const restoring=mode==="restore";
 async function run(){if(!restoring&&!window.confirm("Arquivar este cliente? O histórico será preservado."))return;setBusy(true);setError("");const sb=createSupabaseBrowserClient();const{error:rpcError}=await sb.rpc(restoring?"restore_client":"archive_client",{client_id:clientId});if(rpcError){console.error(`[clientes] ${restoring?"restore":"archive"}_client`,rpcError);setError(rpcError.message);setBusy(false);return}if(restoring){router.refresh()}else{router.push("/clientes");router.refresh()}}
 return <div className="archiveAction"><button type="button" className={`btn ${restoring?"secondary":"dangerButton"}`} disabled={busy} onClick={run}>{restoring?<RotateCcw size={15}/>:<Archive size={15}/>} {busy?"Processando...":restoring?"Restaurar":"Arquivar cliente"}</button>{error&&<span className="inlineError" role="alert">{error}</span>}</div>;
}
