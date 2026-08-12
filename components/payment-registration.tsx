"use client";
import {useState} from "react";
import {useRouter} from "next/navigation";
import {X} from "lucide-react";
import {createSupabaseBrowserClient} from "@/lib/supabase/client";
import {getAuthenticatedProfile} from "@/lib/supabase/profile";
import {money} from "@/lib/erp";
import {saoPauloInputToIso,toLocalInputValue} from "@/lib/date-time.mjs";
const methods=["Pix","Dinheiro","Cartão","Transferência","Boleto","Outro"];

export function PaymentRegistration({serviceId,balance}:{serviceId:string;balance:number}){
 const router=useRouter();const[open,setOpen]=useState(false),[defaultPaidAt,setDefaultPaidAt]=useState(""),[saving,setSaving]=useState(false),[error,setError]=useState(""),[success,setSuccess]=useState("");
 function show(){setError("");setDefaultPaidAt(toLocalInputValue());setOpen(true)}
 async function submit(event:React.FormEvent<HTMLFormElement>){
  event.preventDefault();setSaving(true);setError("");const form=new FormData(event.currentTarget),amount=Number(form.get("amount"));if(amount<=0||amount>balance){setError(`Informe um valor entre R$ 0,01 e ${money(balance)}.`);setSaving(false);return}
  const sb=createSupabaseBrowserClient(),result=await getAuthenticatedProfile(sb);if(!result.ok){console.error("[pagamentos] Profile",result);setError(result.message);setSaving(false);return}
  let paidAt:string;try{paidAt=saoPauloInputToIso(String(form.get("paid_at")))}catch(dateError){setError(dateError instanceof Error?dateError.message:"Data e hora inválidas.");setSaving(false);return}
  const payload={company_id:result.profile.company_id,service_id:serviceId,amount,payment_method:String(form.get("payment_method")),paid_at:paidAt,notes:String(form.get("notes")||"").trim()||null,created_by:result.profile.id};const{error:insertError}=await sb.from("service_payments").insert(payload);if(insertError){console.error("[pagamentos] INSERT service_payments",{error:insertError,payload});setError(insertError.message);setSaving(false);return}
  setOpen(false);setSuccess(`Pagamento de ${money(amount)} registrado com sucesso.`);setSaving(false);router.refresh();
 }
 return <>{balance>0&&<button className="btn" onClick={show}>Registrar pagamento</button>}{success&&<p className="success" role="status">{success}</p>}{open&&<div className="modalBackdrop" role="presentation" onMouseDown={event=>{if(event.target===event.currentTarget&&!saving)setOpen(false)}}><div className="modalCard paymentModal" role="dialog" aria-modal="true" aria-labelledby="payment-title"><div className="modalHeader"><div><h2 id="payment-title">Registrar pagamento</h2><p className="sub">Saldo disponível: {money(balance)}</p></div><button type="button" className="iconButton" aria-label="Fechar" disabled={saving} onClick={()=>setOpen(false)}><X size={20}/></button></div><form className="formGrid" onSubmit={submit}>{error&&<div className="notice formError full" role="alert">{error}</div>}<div className="field"><label>Valor recebido *</label><input name="amount" type="number" min="0.01" max={balance} step="0.01" required autoFocus/></div><div className="field"><label>Forma de pagamento *</label><select name="payment_method" required>{methods.map(method=><option key={method}>{method}</option>)}</select></div><div className="field full"><label>Data do pagamento *</label><input name="paid_at" type="datetime-local" required defaultValue={defaultPaidAt}/><small>Horário de São Paulo</small></div><div className="field full"><label>Observações</label><textarea name="notes" rows={3}/></div><div className="full modalActions"><button type="button" className="btn secondary" disabled={saving} onClick={()=>setOpen(false)}>Cancelar</button><button className="btn" disabled={saving}>{saving?"Registrando...":"Registrar pagamento"}</button></div></form></div></div>}</>;
}
