"use client";

import {useEffect,useMemo,useState} from "react";
import type {ServiceStatus} from "@/lib/erp";

const DAY_MS=24*60*60*1000;
const HOUR_MS=60*60*1000;

function duration(ms:number){
 const safe=Math.max(0,ms);
 const days=Math.floor(safe/DAY_MS);
 const hours=Math.floor((safe%DAY_MS)/HOUR_MS);
 return days>0?`${days} ${days===1?"dia":"dias"} e ${hours}h`:`${hours}h`;
}

function dateTime(value:string){
 return new Intl.DateTimeFormat("pt-BR",{dateStyle:"short",timeStyle:"short",timeZone:"America/Sao_Paulo"}).format(new Date(value)).replace(", "," às ");
}

export function ServiceDeadlineCard({status,deliveredAt,collectedAt,initialNow}:{status:ServiceStatus;deliveredAt:string|null;collectedAt:string|null;initialNow:string}){
 const[now,setNow]=useState(()=>new Date(initialNow).getTime());
 useEffect(()=>{
  if(!deliveredAt||collectedAt||!["delivered","waiting_collection"].includes(status))return;
  const timer=window.setInterval(()=>setNow(Date.now()),60_000);
  return()=>window.clearInterval(timer);
 },[status,deliveredAt,collectedAt]);
 const content=useMemo(()=>{
  if(!deliveredAt)return{tone:"",title:"Prazo não iniciado",lines:["Inicia após confirmar a entrega"]};
  const delivered=new Date(deliveredAt).getTime();
  const deadline=delivered+7*DAY_MS;
  if(status==="completed"){
   if(!collectedAt)return{tone:"completed",title:"Retirado",lines:["Horário da retirada não registrado."]};
   const collected=new Date(collectedAt).getTime();
   const stay=Math.max(0,collected-delivered);
   const exceeded=Math.max(0,collected-deadline);
   return{tone:exceeded>0?"overdue":"completed",title:"Retirado",lines:[`Retirado em: ${dateTime(collectedAt)}`,`Tempo no cliente: ${duration(stay)}`,exceeded>0?`Excedeu o prazo em: ${duration(exceeded)}`:"Retirado dentro do prazo"]};
  }
  if(!["delivered","waiting_collection"].includes(status))return{tone:"",title:"Prazo encerrado",lines:[]};
  const remaining=deadline-now;
  if(remaining<=0)return{tone:"overdue",title:`Atrasado há ${remaining>-HOUR_MS?"menos de 1h":duration(-remaining)}`,lines:[`Prazo: ${dateTime(new Date(deadline).toISOString())}`]};
  if(remaining<DAY_MS)return{tone:"danger",title:`Retirada em ${Math.max(1,Math.ceil(remaining/HOUR_MS))}h`,lines:[`Prazo: ${dateTime(new Date(deadline).toISOString())}`]};
  return{tone:"",title:`${duration(remaining)} restantes`,lines:[`Prazo: ${dateTime(new Date(deadline).toISOString())}`]};
 },[status,deliveredAt,collectedAt,now]);
 return <div className={`card deadlineCard ${content.tone}`}><label>{status==="completed"?"Permanência":"Prazo"}</label><strong>{content.title}</strong>{content.lines.map(line=><p key={line}>{line}</p>)}</div>;
}
