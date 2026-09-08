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

## Variáveis de ambiente

```text
NASA_API_KEY=
TELEGRAM_BOT_TOKEN=
TELEGRAM_CHAT_ID=
TELEGRAM_ALLOWED_USER_ID=
```

## Credencial PostgreSQL

Depois de importar os workflows, abra os nodes PostgreSQL e selecione sua credencial real.
Os JSONs usam o placeholder:

```text
REPLACE_WITH_POSTGRES_CREDENTIAL_ID
```

## Implantação

1. Faça backup do banco antes de aplicar em uma base existente.
2. Execute `database/schema.sql`.
3. Importe os dois workflows.
4. Configure a credencial PostgreSQL.
5. Defina as variáveis de ambiente no container/serviço do n8n.
6. Teste `APOD_Daily_Collector_V2` manualmente.
7. Confirme:
   - APOD criada em `apod_items`;
   - draft criado;
   - imagem de prévia enviada quando aplicável;
   - mensagem com botões recebida;
   - IDs Telegram registrados.
8. Ative `APOD_Approval_Publisher_V2`.
9. Configure o webhook do Telegram para:
   `https://SEU_N8N/webhook/telegram/apod-approval-v2`
10. Teste REJEITAR.
11. Gere um novo draft e teste APROVAR.
12. Na aprovação, o draft deve chegar a `PUBLISHING` e parar no `GATE — Instagram V2`.

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
