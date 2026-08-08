import {AppShell} from "@/components/shell";
import {NotificationList} from "@/components/notification-list";

export default function Notificacoes(){return <AppShell title="Notificações"><div className="heading"><div><h1>Central de Notificações</h1><div className="sub">Alertas operacionais e administrativos da sua empresa.</div></div></div><NotificationList/></AppShell>}
