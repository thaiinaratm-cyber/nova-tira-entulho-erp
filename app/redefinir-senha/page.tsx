"use client";
import Link from "next/link";
import {useEffect,useState} from "react";
import {useRouter} from "next/navigation";
import {Truck} from "lucide-react";
import {createSupabaseBrowserClient} from "@/lib/supabase/client";

export default function RedefinirSenha(){
 const[password,setPassword]=useState("");const[confirmation,setConfirmation]=useState("");const[ready,setReady]=useState(false);const[busy,setBusy]=useState(false);const[error,setError]=useState("");const router=useRouter();
 useEffect(()=>{const sb=createSupabaseBrowserClient();sb.auth.getUser().then(({data,error:authError})=>{if(authError||!data.user){console.error("[redefinição] Sessão de recuperação",authError);setError("O link de recuperação é inválido ou expirou.");return}setReady(true)})},[]);
 async function submit(event:React.FormEvent){event.preventDefault();if(password.length<8){setError("A nova senha deve ter pelo menos 8 caracteres.");return}if(password!==confirmation){setError("As senhas não coincidem.");return}setBusy(true);setError("");const sb=createSupabaseBrowserClient();const{error:updateError}=await sb.auth.updateUser({password});if(updateError){console.error("[redefinição] updateUser",updateError);setError(`Não foi possível redefinir a senha: ${updateError.message}`);setBusy(false);return}await sb.auth.signOut();router.replace("/login?password=updated")}
 return <div className="authPage"><form className="card formCard authCard" onSubmit={submit}><div className="authBrand"><span className="brandMark"><Truck size={20}/></span><b>Nova Tira Entulho</b></div><h1>Definir nova senha</h1>{error&&<div className="notice formError" role="alert">{error}</div>}{ready?<><p className="sub">Use uma senha forte com pelo menos 8 caracteres.</p><div className="field"><label>Nova senha</label><input type="password" required minLength={8} autoComplete="new-password" value={password} onChange={e=>setPassword(e.target.value)}/></div><div className="field"><label>Confirmar nova senha</label><input type="password" required minLength={8} autoComplete="new-password" value={confirmation} onChange={e=>setConfirmation(e.target.value)}/></div><button className="btn authButton" disabled={busy}>{busy?"Salvando...":"Redefinir senha"}</button></>:error&&<Link className="btn secondary authButton" href="/esqueci-senha">Solicitar novo link</Link>}</form></div>;
}
