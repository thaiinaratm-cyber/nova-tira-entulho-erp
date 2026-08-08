"use client";
import Link from "next/link";
import {useState} from "react";
import {Truck} from "lucide-react";
import {createSupabaseBrowserClient} from "@/lib/supabase/client";

export default function EsqueciSenha(){
 const[email,setEmail]=useState("");const[busy,setBusy]=useState(false);const[error,setError]=useState("");const[sent,setSent]=useState(false);
 async function submit(event:React.FormEvent){event.preventDefault();setBusy(true);setError("");const sb=createSupabaseBrowserClient();const redirectTo=`${window.location.origin}/auth/callback?next=/redefinir-senha`;const{error:resetError}=await sb.auth.resetPasswordForEmail(email.trim(),{redirectTo});if(resetError){console.error("[recuperação] resetPasswordForEmail",resetError);setError(`Não foi possível enviar o e-mail: ${resetError.message}`);setBusy(false);return}setSent(true);setBusy(false)}
 return <div className="authPage"><form className="card formCard authCard" onSubmit={submit}><div className="authBrand"><span className="brandMark"><Truck size={20}/></span><b>Nova Tira Entulho</b></div><h1>Recuperar senha</h1>{sent?<><div className="notice successNotice" role="status">Se o e-mail estiver cadastrado, você receberá um link seguro para redefinir sua senha.</div><Link className="btn secondary authButton" href="/login">Voltar ao login</Link></>:<><p className="sub">Informe o e-mail da sua conta. Enviaremos as instruções de recuperação.</p>{error&&<div className="notice formError" role="alert">{error}</div>}<div className="field"><label htmlFor="email">E-mail</label><input id="email" type="email" required autoComplete="email" value={email} onChange={e=>setEmail(e.target.value)}/></div><button className="btn authButton" disabled={busy}>{busy?"Enviando...":"Enviar link de recuperação"}</button><Link className="authLink" href="/login">Voltar ao login</Link></>}</form></div>;
}
