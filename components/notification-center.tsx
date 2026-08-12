"use client";
import Link from "next/link";
import {useEffect,useRef,useState} from "react";
import {usePathname,useRouter} from "next/navigation";
import {Bell} from "lucide-react";
import {createSupabaseBrowserClient} from "@/lib/supabase/client";
import {formatDateTime} from "@/lib/date-time.mjs";

export type NotificationRow={id:string;type:string;title:string;message:string;action_url:string|null;is_read:boolean;created_at:string};
export const notificationTone=(type:string)=>type==="overdue"?"urgent":type==="deadline_soon"||type==="collection_today"||type==="payment_pending"||type==="low_availability"?"attention":"info";
export const notificationTypeLabel=(type:string)=>({delivery_today:"Entrega",collection_today:"Retirada",deadline_soon:"Prazo próximo",overdue:"Atraso",payment_pending:"Pagamento",low_availability:"Disponibilidade"}[type]||"Alerta");

export function NotificationCenter(){
 const[rows,setRows]=useState<NotificationRow[]>([]);const[unread,setUnread]=useState(0);const[open,setOpen]=useState(false);const box=useRef<HTMLDivElement>(null);const pathname=usePathname();const router=useRouter();
 async function load(){const sb=createSupabaseBrowserClient();const{error:generateError}=await sb.rpc("generate_operational_notifications");if(generateError)console.error("[notificações] geração",generateError);const[{data,error},{count,error:countError}]=await Promise.all([sb.from("notifications").select("id,type,title,message,action_url,is_read,created_at").order("created_at",{ascending:false}).limit(7),sb.from("notifications").select("id",{count:"exact",head:true}).eq("is_read",false)]);if(error||countError){console.error("[notificações] consulta",{error,countError});return}setRows((data||[]) as NotificationRow[]);setUnread(count||0)}
 useEffect(()=>{load()},[pathname]);
 useEffect(()=>{function outside(event:MouseEvent){if(box.current&&!box.current.contains(event.target as Node))setOpen(false)}document.addEventListener("mousedown",outside);return()=>document.removeEventListener("mousedown",outside)},[]);
 async function openNotification(row:NotificationRow){setOpen(false);if(!row.is_read){setRows(current=>current.map(item=>item.id===row.id?{...item,is_read:true}:item));setUnread(value=>Math.max(0,value-1));const{error}=await createSupabaseBrowserClient().from("notifications").update({is_read:true,read_at:new Date().toISOString()}).eq("id",row.id);if(error)console.error("[notificações] marcar lida",error)}if(row.action_url)router.push(row.action_url)}
 return <div className="notificationCenter" ref={box}><button type="button" className="notificationBell" aria-label={`${unread} notificações não lidas`} aria-expanded={open} onClick={()=>setOpen(value=>!value)}><Bell size={19}/>{unread>0&&<span>{unread>99?"99+":unread}</span>}</button>{open&&<div className="notificationDropdown" role="dialog" aria-label="Notificações recentes"><div className="notificationDropdownHeader"><b>Notificações</b><small>{unread} não lida{unread===1?"":"s"}</small></div><div className="notificationDropdownList">{rows.length===0?<p className="notificationEmpty">Nenhuma notificação.</p>:rows.map(row=><button type="button" className={`notificationPreview ${notificationTone(row.type)} ${row.is_read?"read":"unread"}`} key={row.id} onClick={()=>openNotification(row)}><span className="notificationDot"/><span><b>{row.title}</b><small>{row.message}</small><time>{formatDateTime(row.created_at)}</time></span></button>)}</div><Link className="notificationAll" href="/notificacoes" onClick={()=>setOpen(false)}>Ver todas as notificações</Link></div>}</div>;
}
