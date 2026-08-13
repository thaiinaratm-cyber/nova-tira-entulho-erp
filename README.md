# Pátio ERP

ERP para locação de caçambas, com Next.js, TypeScript, Tailwind CSS e Supabase.

## Configuração
1. Execute `supabase/schema.sql` no SQL Editor do Supabase.
2. Copie `.env.example` para `.env.local` e informe URL e chave anônima.
3. Crie uma empresa e um usuário no Supabase Auth; insira o `profile` vinculando os UUIDs.
4. Insira em `settings`: `key = 'total_dumpsters'` e `value = 50` (ou a quantidade real).

## Execução
`npm install` e `npm run dev`. Para validar produção: `npm run build`.

Sem variáveis configuradas a interface funciona em modo de demonstração, sem persistência.

## Configurações da empresa
Para bancos criados antes desta personalização, execute `supabase/migrations/20260807000200_company_profile.sql`. Os dados são lidos da tabela `companies`; funcionários têm leitura e apenas administradores podem atualizar.
