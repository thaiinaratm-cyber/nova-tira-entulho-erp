import fs from "node:fs";
import path from "node:path";
import {createClient} from "@supabase/supabase-js";

export const DEMO_BATCH="DEMO_PORTFOLIO_V1";
export const clientIds=Array.from({length:8},(_,i)=>`d1000000-0000-4000-8000-${String(i+1).padStart(12,"0")}`);
export const addressIds=Array.from({length:8},(_,i)=>`d2000000-0000-4000-8000-${String(i+1).padStart(12,"0")}`);
export const serviceIds=Array.from({length:15},(_,i)=>`d3000000-0000-4000-8000-${String(i+1).padStart(12,"0")}`);
export const paymentIds=Array.from({length:5},(_,i)=>`d4000000-0000-4000-8000-${String(i+1).padStart(12,"0")}`);
function loadEnv(){const file=path.resolve(".env.local");if(!fs.existsSync(file))return;for(const line of fs.readFileSync(file,"utf8").split(/\r?\n/)){const m=line.match(/^\s*([A-Z0-9_]+)\s*=\s*(.*)\s*$/);if(!m||process.env[m[1]])continue;let value=m[2];if((value.startsWith('"')&&value.endsWith('"'))||(value.startsWith("'")&&value.endsWith("'")))value=value.slice(1,-1);process.env[m[1]]=value}}
export function context(){loadEnv();const url=process.env.NEXT_PUBLIC_SUPABASE_URL,key=process.env.SUPABASE_SERVICE_ROLE_KEY,companyId=process.env.DEMO_COMPANY_ID;if(!url||!key||!companyId)throw new Error("Configure NEXT_PUBLIC_SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY e DEMO_COMPANY_ID em .env.local.");if(!["127.0.0.1","localhost","host.docker.internal"].includes(new URL(url).hostname))throw new Error("Seed DEMO bloqueado: o Supabase configurado não é local.");if(!/^[0-9a-f]{8}-[0-9a-f-]{27}$/i.test(companyId))throw new Error("DEMO_COMPANY_ID deve ser um UUID válido.");return{companyId,supabase:createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}})}}
export async function assertCompany(sb,id){const{data,error}=await sb.from("companies").select("id,name").eq("id",id).single();if(error||!data)throw new Error(`Empresa DEMO não encontrada: ${error?.message||id}`);return data}
export function fail(error){console.error("\n[DEMO] Falha:",error);process.exitCode=1}
