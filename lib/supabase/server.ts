import {createServerClient} from "@supabase/ssr";
import {cookies} from "next/headers";
import {getSupabasePublicConfig} from "./environment";
export async function createSupabaseServerClient(){const store=await cookies(),{url,key}=getSupabasePublicConfig();return createServerClient(url,key,{cookies:{getAll:()=>store.getAll(),setAll:(items)=>{try{items.forEach(({name,value,options})=>store.set(name,value,options))}catch{}}}})}
