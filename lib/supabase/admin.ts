import {createClient} from "@supabase/supabase-js";
import {getSupabasePublicConfig,getSupabaseServiceRoleKey} from "./environment";
export function createSupabaseAdminClient(){const{url}=getSupabasePublicConfig(),key=getSupabaseServiceRoleKey();return createClient(url,key,{auth:{autoRefreshToken:false,persistSession:false}})}
