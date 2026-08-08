"use client";

import Link from "next/link";
import {useEffect,useState} from "react";
import {Truck} from "lucide-react";
import {useRouter} from "next/navigation";
import {createSupabaseBrowserClient} from "@/lib/supabase/client";

export default function Login(){
  const[email,setEmail]=useState("");
  const[password,setPassword]=useState("");
  const[error,setError]=useState("");
  const[success,setSuccess]=useState("");
  const[busy,setBusy]=useState(false);
  const router=useRouter();

  useEffect(()=>{
    const params=new URLSearchParams(window.location.search);
    if(params.get("error")==="inactive")setError("Esta conta está inativa. Procure um administrador.");
    if(params.get("error")==="recovery")setError("O link de recuperação é inválido ou expirou. Solicite um novo link.");
    if(params.get("password")==="updated")setSuccess("Senha redefinida com sucesso. Entre com a nova senha.");
  },[]);

  async function submit(event:React.FormEvent){
    event.preventDefault();
    setBusy(true);setError("");setSuccess("");
    const sb=createSupabaseBrowserClient();
    const{data,error:loginError}=await sb.auth.signInWithPassword({email,password});
    if(loginError||!data.user){setError("E-mail ou senha inválidos.");setBusy(false);return}
    const{data:profile,error:profileError}=await sb.from("profiles").select("is_active").eq("id",data.user.id).maybeSingle();
    if(profileError||!profile?.is_active){
      console.error("[login] Falha ao validar perfil",profileError);
      await sb.auth.signOut();
      setError(profileError?"Não foi possível validar o perfil desta conta.":"Esta conta está inativa. Procure um administrador.");
      setBusy(false);return;
    }
    router.replace("/dashboard");router.refresh();
  }

  return <div className="loginPage"><section className="loginArt"><div className="brand"><span className="brandMark"><Truck/></span>Nova Tira Entulho</div><h1>Sua operação sob controle, do pátio à retirada.</h1><p>Organize clientes, entregas, prazos e pagamentos em um só lugar.</p></section><section className="loginBox"><form className="formCard" onSubmit={submit}><h2>Bem-vindo de volta</h2><p className="sub">Entre para acessar o painel operacional.</p>{error&&<div className="notice formError" role="alert">{error}</div>}{success&&<div className="notice successNotice" role="status">{success}</div>}<div className="field"><label>E-mail</label><input type="email" required value={email} onChange={e=>setEmail(e.target.value)} autoComplete="email"/></div><div className="field"><div className="fieldHeading"><label>Senha</label><Link className="textButton" href="/esqueci-senha">Esqueci minha senha</Link></div><input type="password" required value={password} onChange={e=>setPassword(e.target.value)} autoComplete="current-password"/></div><button className="btn" style={{width:"100%"}} disabled={busy}>{busy?"Entrando...":"Entrar no sistema"}</button></form></section></div>;
}
