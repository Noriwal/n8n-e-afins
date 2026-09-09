# APOD → Telegram → Instagram — Fundação V2

Esta versão corrige os principais problemas identificados na primeira fundação.

## Melhorias da V2

- callback_data curto: `a:<approval_key>` e `r:<approval_key>`;
- `approval_key` aleatória de 24 caracteres hex;
- nenhum segredo é enviado no botão;
- operações SQL recebem um único JSONB parametrizado;
- ingestão APOD + criação do draft centralizadas no PostgreSQL;
- aprovação/rejeição com `FOR UPDATE`, evitando dupla transição;
- expiração gera evento apenas quando ocorre a transição;
- estados `UNSUPPORTED` e `PUBLISH_ERROR`;
- tabela `publication_attempts`;
- `answerCallbackQuery` implementado;
- remoção dos botões após processamento;
- publicação no Instagram continua atrás de um GATE;
- Collector envia imagem de prévia quando disponível;
- Draft duplicado não envia uma nova mensagem Telegram.

## Arquivos

- `database/schema.sql`
- `n8n/workflow-apod-collector-v2.json`
- `n8n/workflow-approval-publisher-v2.json`
- `.env.example`
- `scripts/generate-env.ps1`
- `scripts/generate-env.sh`
- `scripts/discover-telegram-ids.ps1`
- `scripts/discover-telegram-ids.sh`

## Bootstrap automático de chaves e segredos

Nunca coloque o arquivo `.env` no Git. O `.gitignore` deste projeto já o protege.

Os scripts de bootstrap geram automaticamente segredos locais criptograficamente aleatórios para:

- `POSTGRES_ADMIN_PASSWORD`
- `POSTGRES_PASSWORD`
- `REDIS_PASSWORD`
- `N8N_ENCRYPTION_KEY`
- `TELEGRAM_WEBHOOK_SECRET`

As credenciais que pertencem a serviços externos não podem ser inventadas localmente e continuam sendo obtidas nos respectivos provedores:

- `NASA_API_KEY`
- `TELEGRAM_BOT_TOKEN`
- `INSTAGRAM_ACCESS_TOKEN`
- `INSTAGRAM_ACCOUNT_ID`

### Windows / PowerShell

Na raiz do repositório:

```powershell
.\scripts\generate-env.ps1
```

Para recriar deliberadamente o `.env`:

```powershell
.\scripts\generate-env.ps1 -Force
```

Depois, preencha `TELEGRAM_BOT_TOKEN`, envie uma mensagem para o bot e execute:

```powershell
.\scripts\discover-telegram-ids.ps1
```

O script consulta `getUpdates` e preenche automaticamente:

```text
TELEGRAM_CHAT_ID=
TELEGRAM_ALLOWED_USER_ID=
```

### Linux / macOS

```bash
chmod +x scripts/*.sh
./scripts/generate-env.sh
```

Para recriar:

```bash
./scripts/generate-env.sh --force
```

Depois de preencher o token do bot e enviar uma mensagem para ele:

```bash
./scripts/discover-telegram-ids.sh
```

## Variáveis de ambiente principais

```text
POSTGRES_ADMIN_USER=postgres
POSTGRES_ADMIN_PASSWORD=<gerado>
POSTGRES_USER=n8n
POSTGRES_PASSWORD=<gerado>
POSTGRES_DB=n8n
REDIS_PASSWORD=<gerado>
N8N_ENCRYPTION_KEY=<gerado>
TELEGRAM_WEBHOOK_SECRET=<gerado>
NASA_API_KEY=
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
TELEGRAM_ALLOWED_USER_ID=
INSTAGRAM_ACCESS_TOKEN=
INSTAGRAM_ACCOUNT_ID=
```

## Credencial PostgreSQL

Depois de importar os workflows, abra os nodes PostgreSQL e selecione sua credencial real.
Os JSONs usam o placeholder:

```text
REPLACE_WITH_POSTGRES_CREDENTIAL_ID
```

## Implantação

1. Clone o repositório.
2. Execute o gerador de `.env` apropriado ao sistema operacional.
3. Preencha as credenciais externas necessárias.
4. Execute `database/schema.sql`.
5. Importe os dois workflows.
6. Configure a credencial PostgreSQL.
7. Defina as variáveis de ambiente no container/serviço do n8n.
8. Teste `APOD_Daily_Collector_V2` manualmente.
9. Confirme:
   - APOD criada em `apod_items`;
   - draft criado;
   - imagem de prévia enviada quando aplicável;
   - mensagem com botões recebida;
   - IDs Telegram registrados.
10. Ative `APOD_Approval_Publisher_V2`.
11. Configure o webhook do Telegram para:
    `https://SEU_N8N/webhook/telegram/apod-approval-v2`
12. Teste REJEITAR.
13. Gere um novo draft e teste APROVAR.
14. Na aprovação, o draft deve chegar a `PUBLISHING` e parar no `GATE — Instagram V2`.

## Observação sobre tradução

`description_pt` ainda contém o texto original. A próxima fase deve inserir tradução pt-BR antes da ingestão no banco.

## Observação sobre vídeo

Vídeo permanece `UNSUPPORTED` nesta fundação. Na próxima fase devemos resolver:
- vídeo direto MP4;
- YouTube/Vimeo;
- download/transcodificação quando necessário;
- requisitos do Instagram Reel.

## Próxima fase

1. tradução pt-BR;
2. validação técnica de imagem;
3. Instagram Graph API;
4. criação de container;
5. polling do container;
6. publicação;
7. atualização `PUBLISHED`/`PUBLISH_ERROR`;
8. retries controlados usando `publication_attempts`.
