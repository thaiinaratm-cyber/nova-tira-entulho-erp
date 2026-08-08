export type Company={id?:string;name:string;document:string;address:string;number:string;neighborhood:string;city:string;state:string;zip_code:string;phone:string;whatsapp:string;email:string;logo_url:string};
// Fallback único para desenvolvimento sem Supabase. Em produção, companies é a fonte oficial.
export const defaultCompany:Company={name:"Nova Tira Entulho",document:"12.566.272/0001-32",address:"Avenida Mário Covas Júnior",number:"2222",neighborhood:"Bairro do Portão",city:"",state:"",zip_code:"",phone:"4653-3261",whatsapp:"(11) 94569-0387",email:"",logo_url:""};
export const companyInitials=(name:string)=>name.split(/\s+/).slice(0,2).map(x=>x[0]).join("").toUpperCase();
