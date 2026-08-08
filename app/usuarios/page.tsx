import {redirect} from "next/navigation";
import {AppShell} from "@/components/shell";
import {UsersManager} from "@/components/users-manager";
import {requireAdminAccess} from "@/lib/auth";
export const dynamic="force-dynamic";
export default async function Usuarios(){const access=await requireAdminAccess();if(!access.ok)redirect(access.status===401?"/login":"/dashboard");return <AppShell title="Usuários"><UsersManager/></AppShell>}
