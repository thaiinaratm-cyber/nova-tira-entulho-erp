"use client";
import Link from "next/link";
import {useEffect,useState} from "react";
import {usePathname} from "next/navigation";
import {LayoutDashboard,Users,ClipboardList,CalendarDays,UserCog,Settings,Archive,LogOut,Menu,X} from "lucide-react";
import {companyInitials,defaultCompany} from "@/lib/company";
import {NotificationCenter} from "@/components/notification-center";
import {createSupabaseBrowserClient} from "@/lib/supabase/client";

const operational=[{href:"/dashboard",label:"Dashboard",Icon:LayoutDashboard},{href:"/clientes",label:"Clientes",Icon:Users},{href:"/servicos",label:"Serviços",Icon:ClipboardList},{href:"/agenda",label:"Agenda",Icon:CalendarDays}];
const administrative=[{href:"/usuarios",label:"Usuários",Icon:UserCog},{href:"/arquivados",label:"Arquivados",Icon:Archive},{href:"/configuracoes",label:"Configurações",Icon:Settings}];

export function AppShell({children,title}:{children:React.ReactNode;title:string}){
 const pathname=usePathname();const[company,setCompany]=useState(defaultCompany);const[role,setRole]=useState<"admin"|"employee">("employee");const[menuOpen,setMenuOpen]=useState(false);
 useEffect(()=>{async function load(){const sb=createSupabaseBrowserClient();const{data:{user}}=await sb.auth.getUser();if(!user)return;const{data:profile}=await sb.from("profiles").select("role,company_id,is_active").eq("id",user.id).maybeSingle();if(!profile?.is_active)return;setRole(profile.role);const{data}=await sb.from("companies").select("*").eq("id",profile.company_id).maybeSingle();if(data)setCompany({...defaultCompany,...data})}load()},[]);
 const items=role==="admin"?[...operational,...administrative]:operational;
 async function logout(){const sb=createSupabaseBrowserClient();await sb.auth.signOut();window.location.href="/login"}
 return <div className="shell"><button className={`mobileOverlay ${menuOpen?"open":""}`} aria-label="Fechar menu" onClick={()=>setMenuOpen(false)}/><aside className={`sidebar ${menuOpen?"open":""}`}><button className="mobileClose" aria-label="Fechar menu" onClick={()=>setMenuOpen(false)}><X size={20}/></button><div className="brand">{company.logo_url?<img className="companyLogo" src={company.logo_url} alt={`Logo ${company.name}`}/>:<span className="brandMark">{companyInitials(company.name)}</span>}<span><b>{company.name}</b><small>Gestão de caçambas</small></span></div>{process.env.NODE_ENV==="development"&&<div className="devEnvironmentBadge">AMBIENTE DE TESTE</div>}<nav className="nav">{items.map(({href,label,Icon})=><Link key={href} href={href} onClick={()=>setMenuOpen(false)} className={pathname.startsWith(href)?"active":""}><Icon size={18}/>{label}</Link>)}</nav><div className="sideFoot">{company.phone} · v1.0</div></aside><main className="main"><header className="topbar"><button className="mobileToggle btn secondary" aria-label="Abrir menu" onClick={()=>setMenuOpen(true)}><Menu size={18}/></button><span className="topTitle"><b>{company.name}</b><span className="headerDivider">/</span>{title}</span>{process.env.NODE_ENV==="development"&&<span className="devTopBadge">DEV</span>}<div className="user"><NotificationCenter/><div className="avatar" aria-hidden="true">{role==="admin"?"AD":"FN"}</div><b className="headerRole">{role==="admin"?"Administrador":"Funcionário"}</b><button className="logoutButton" title="Sair" aria-label="Sair" onClick={logout}><LogOut size={17}/></button></div></header><div className="content">{children}</div></main></div>;
}
