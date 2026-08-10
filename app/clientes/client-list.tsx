"use client";
import {useState} from "react";
import Link from "next/link";

type ClientRow={id:string;name:string;document:string|null;phone:string;city:string|null;addressSearch:string;serviceCount:number;totalSpent:number;pendingAmount:number};
const money=(value:number)=>value.toLocaleString("pt-BR",{style:"currency",currency:"BRL"});
const normalize=(value:string)=>value.normalize("NFD").replace(/[\u0300-\u036f]/g,"").toLocaleLowerCase("pt-BR").trim();

export function ClientList({clients}:{clients:ClientRow[]}){
 const[query,setQuery]=useState("");const normalizedQuery=normalize(query);const rows=clients.filter(client=>normalize(`${client.name} ${client.phone} ${client.document||""} ${client.addressSearch}`).includes(normalizedQuery));
 return <><div className="toolbar"><input className="search" aria-label="Buscar clientes" placeholder="Buscar por nome, telefone, CPF/CNPJ ou endereço" value={query} onChange={event=>setQuery(event.target.value)}/></div>{rows.length===0?<div className="card emptyState">{clients.length===0?"Nenhum cliente cadastrado.":"Nenhum cliente encontrado para esta busca."}</div>:<div className="tableWrap"><table><thead><tr><th>Cliente</th><th>Telefone</th><th>Cidade</th><th>Serviços</th><th>Total gasto</th><th>Pendente</th><th></th></tr></thead><tbody>{rows.map(client=><tr key={client.id}><td><b>{client.name}</b><div className="sub">{client.document||"Sem documento"}</div></td><td>{client.phone}</td><td>{client.city||"—"}</td><td>{client.serviceCount}</td><td>{money(client.totalSpent)}</td><td>{money(client.pendingAmount)}</td><td><Link href={`/clientes/${client.id}`}>Ver detalhes →</Link></td></tr>)}</tbody></table></div>}</>;
}
