export const DUMPSTER_TERM_MS=7*24*60*60*1000;
export type DumpsterTimingInput={status:string;delivery_scheduled_at?:string|null;delivered_at?:string|null;deadline_at?:string|null;collected_at?:string|null};
export type DumpsterTiming={baseAt:string|null;deadlineAt:string|null;scheduledAt:string|null;remainingMs:number|null;overdueMs:number;stayMs:number|null;tone:"scheduled"|"normal"|"near"|"overdue"|"collected"|"cancelled";label:string};
const duration=(milliseconds:number)=>{const safe=Math.max(0,milliseconds),days=Math.floor(safe/86400000),hours=Math.floor((safe%86400000)/3600000);return days?`${days} dia${days===1?"":"s"} e ${hours}h`:`${hours}h`};
export function calculateDumpsterTiming(input:DumpsterTimingInput,nowValue:Date|string|number=new Date()):DumpsterTiming{
 const now=new Date(nowValue).getTime(),base=input.delivered_at?new Date(input.delivered_at).getTime():null;
 const officialDeadline=base===null?null:base+DUMPSTER_TERM_MS;
 const deadlineAt=officialDeadline===null?(input.deadline_at||null):new Date(officialDeadline).toISOString();
 const common={baseAt:input.delivered_at||null,deadlineAt,scheduledAt:input.delivery_scheduled_at||null};
 if(input.status==="cancelled")return{...common,remainingMs:null,overdueMs:0,stayMs:null,tone:"cancelled",label:"Operação cancelada"};
 if(input.status==="collected"&&base!==null&&input.collected_at){const stay=Math.max(0,new Date(input.collected_at).getTime()-base);return{...common,remainingMs:0,overdueMs:Math.max(0,stay-DUMPSTER_TERM_MS),stayMs:stay,tone:"collected",label:"Caçamba retirada"}}
 if(base===null)return{...common,remainingMs:null,overdueMs:0,stayMs:null,tone:"scheduled",label:"Prazo não iniciado"};
 const remaining=officialDeadline!-now;if(remaining<=0)return{...common,remainingMs:remaining,overdueMs:-remaining,stayMs:null,tone:"overdue",label:`Atrasada há ${duration(-remaining)}`};
 return{...common,remainingMs:remaining,overdueMs:0,stayMs:null,tone:remaining<86400000?"near":"normal",label:remaining<86400000?`Retirada em ${Math.max(1,Math.ceil(remaining/3600000))}h`:`${duration(remaining)} restantes`};
}
export const dumpsterDayKey=(value:string|null)=>value?new Intl.DateTimeFormat("en-CA",{timeZone:"America/Sao_Paulo",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date(value)):null;
