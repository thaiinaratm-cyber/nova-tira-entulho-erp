# Configuração de recuperação de senha

No Supabase, abra **Authentication > Email Templates > Reset Password** e cole o conteúdo de `recovery.html`.

Em **Authentication > URL Configuration**:

- Site URL local: `http://localhost:3000`
- Redirect URL local: `http://localhost:3000/auth/callback`
- Produção: `https://SEU-DOMINIO.vercel.app/auth/callback`

Mantenha as URLs de preview estritamente necessárias na allowlist. Em produção, configure SMTP próprio em **Project Settings > Authentication > SMTP Settings**, com remetente do domínio da empresa, SPF, DKIM e DMARC.
