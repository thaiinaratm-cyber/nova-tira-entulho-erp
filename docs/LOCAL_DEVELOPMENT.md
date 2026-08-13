# Desenvolvimento local seguro

Este projeto usa dois ambientes completamente separados:

- `localhost:3000` → Supabase local em `127.0.0.1:54321`.
- Vercel → Supabase de produção configurado exclusivamente nas Environment Variables da Vercel.

Nunca copie chaves da Vercel para `.env.local`. O arquivo local é ignorado pelo Git e o ERP bloqueia a inicialização em modo development quando a URL do Supabase não é local.

## Pré-requisitos

1. Docker Desktop aberto.
2. Supabase CLI. É possível usar sem instalação global com `npx supabase`.

Para instalar no projeto, opcionalmente:

```powershell
npm install --save-dev supabase
```

Depois disso, use `npx supabase ...`. Se o executável `supabase` já estiver no PATH, os mesmos comandos funcionam sem `npx`.

## Primeira inicialização

Na raiz do ERP:

```powershell
npx supabase start
npx supabase status
```

O primeiro comando baixa e inicia os containers. O segundo mostra a API URL, a chave pública local, a service role local, Studio e Mailpit.

Copie `.env.example` para `.env.local` e use somente os valores mostrados pelo ambiente local:

```env
NEXT_PUBLIC_SUPABASE_URL=http://127.0.0.1:54321
NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<publishable ou anon key local>
SUPABASE_SERVICE_ROLE_KEY=<service role key local>
DEMO_COMPANY_ID=10000000-0000-4000-8000-000000000001
```

Se sua versão do CLI mostrar `ANON_KEY` em vez de publishable key, ela pode ser colocada em `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`. O ERP também aceita temporariamente `NEXT_PUBLIC_SUPABASE_ANON_KEY` como fallback.

Reinicie o Next.js sempre que alterar o `.env.local`:

```powershell
npm run dev
```

## Banco e dados fictícios

`supabase db reset` executa, nesta ordem:

1. A migration inicial `20260806000100_initial_schema.sql`.
2. Todas as migrations incrementais existentes.
3. `supabase/seed.sql`.

O seed cria somente dados fictícios locais: empresa `Nova Tira Entulho — DEV`, 80 caçambas, três clientes, quatro OS e dois usuários.

Credenciais exclusivamente locais:

| Perfil | E-mail | Senha |
|---|---|---|
| Administrador | `admin@teste.local` | `DevLocal#2026` |
| Funcionário | `funcionario@teste.local` | `DevLocal#2026` |

Não reutilize essas senhas em produção.

## Comandos cotidianos

```powershell
# Iniciar
npx supabase start
npm run dev

# Consultar URLs e chaves locais
npx supabase status

# Recriar banco, aplicar migrations e repopular o seed
npx supabase db reset

# Parar os containers locais
npx supabase stop
```

## E-mails locais

Recuperação de senha e demais mensagens ficam no Mailpit local; nenhum e-mail real é enviado. A URL é mostrada por `npx supabase status` e, com as portas padrão deste projeto, é `http://127.0.0.1:54324`.

## Como confirmar que está seguro

1. A URL em `.env.local` deve começar com `http://127.0.0.1:54321` ou `http://localhost:54321`.
2. O menu mostra `AMBIENTE DE TESTE` e o cabeçalho mostra `DEV` quando `npm run dev` está ativo.
3. O nome da empresa local é `Nova Tira Entulho — DEV`.
4. Supabase Studio local abre em `http://127.0.0.1:54323`.
5. Se development receber uma URL remota, o ERP interrompe a inicialização com: `Ambiente local está apontando para o Supabase de produção. Corrija o .env.local.`

## Produção na Vercel

Não altere as variáveis existentes do projeto na Vercel. O arquivo `.env.local` não é enviado ao Git nem à Vercel. O deployment continua lendo `NEXT_PUBLIC_SUPABASE_URL`, a chave pública e `SUPABASE_SERVICE_ROLE_KEY` cadastradas no painel da Vercel.

Antes de validar isolamento, crie um cliente claramente fictício no localhost e confirme no Studio local. Depois consulte a aplicação de produção e confirme que o registro não existe lá; não use a service role ou SQL remoto para esse teste.
