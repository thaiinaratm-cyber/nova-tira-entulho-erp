import type {Metadata} from "next";
import "./globals.css";
import "./safe-actions.css";
import "./notifications.css";

export const metadata:Metadata={title:"Pátio ERP | Gestão de Caçambas",description:"Gestão operacional para locação de caçambas"};
export default function RootLayout({children}:{children:React.ReactNode}){return <html lang="pt-BR"><body>{children}</body></html>}
