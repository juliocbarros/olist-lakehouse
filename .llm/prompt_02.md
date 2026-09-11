# Prompt 2 · CI/CD com GitHub Actions e OIDC — deploy sem clicar, sem token salvo

**Entrega:** três workflows do GitHub Actions (`validate`, `deploy-dev`,
`deploy-prod`) autenticando no Databricks via *workload identity federation*
(OIDC) — nenhum token ou senha salvo em secret do repositório. **Deploy nº 2.**

> **A resposta direta ao que já existia.** Até agora, todo `bundle deploy`
> saiu do terminal do VS Code, na sua máquina, com seu profile. Hoje um push
> na `main` faz o dev se atualizar sozinho, e um PR já falha antes do merge
> se o bundle estiver errado — sem ninguém precisar rodar nada na mão.

---

## O que mostrar antes

**1 · O repositório não sabe que o Databricks existe**

```bash
# não há nenhum workflow ainda
ls .github/workflows/ 2>&1 || echo 'pasta não existe'
```

**2 · Um push na main não muda nada no workspace**

```sql
-- anote o updated_at atual de qualquer tabela gold
SELECT max(_processado_em) FROM lakehouse_olist.gold.dim_cliente;
```

Faça uma alteração pequena (um comentário a mais num `.sql`, por exemplo),
dê `git push` na `main`, e volte no Catalog Explorer: nada mudou, porque
nada além do seu terminal sabe fazer deploy.

**A pergunta para quem for revisar isso depois:** *"o que precisa ser
verdade para eu confiar que o que está rodando em produção é exatamente o
que está na branch main — sem eu ter que lembrar de rodar `deploy` na mão?"*

---

**Enquanto ele trabalha, você explica:**

- **OIDC em vez de token salvo.** Um Personal Access Token guardado como
  secret do GitHub é uma senha de longa duração vivendo fora do seu
  controle. Com OIDC, o GitHub emite um token de vida curta a cada execução
  do workflow, e o Databricks troca esse token por acesso — não existe
  segredo para vazar, porque não existe segredo salvo.
- **A política de federação é quem decide em quem confiar.** Ela amarra
  três coisas: o repositório GitHub exato (`juliocbarros/olist-lakehouse`),
  o Service Principal do Databricks, e o *environment* do GitHub que disparou
  o workflow (`dev` ou `prod`). Sem essa combinação batendo, o token é
  recusado — mesmo que alguém tenha o Application ID.
- **Por que `prod` é `workflow_dispatch`, não `push`.** Dev pode se atualizar
  sozinho a cada push — é onde o erro é barato. Prod só roda quando alguém
  aperta o botão, e o GitHub Environment com *required reviewer* exige
  aprovação antes de rodar, mesmo depois do clique.
- **`permissions: id-token: write` é o que libera o OIDC.** Sem essa linha
  no workflow, o GitHub nem emite o token — é a permissão mais fácil de
  esquecer e mais fácil de não perceber que falta, porque o erro só aparece
  na hora da autenticação, não no lint do YAML.

---

## O prompt

```
Adicione CI/CD ao projeto em C:\Users\julio\...\Olist_DataEnginier, que já
está com o bundle completo (raw → bronze → silver → gold) validado.

CONTEXTO
- repositório GitHub já configurado como origin: juliocbarros/olist-lakehouse
  (repositório é a raiz de Documentos; o projeto vive em
  Projetos/Olist/Olist_DataEnginier dentro dele)
- host: https://dbc-604bc86c-0b09.cloud.databricks.com
- targets do bundle: dev (default) e prod, já existentes no databricks.yml

ESCOPO
- PR que tocar no projeto → só valida (databricks bundle validate --target dev)
- push na main → deploy automático no target dev
- prod → só manual (workflow_dispatch), nunca automático

AUTENTICAÇÃO: workload identity federation (OIDC), sem PAT nem secret salvo.

1. .github/workflows/olist-validate.yml
   on: pull_request, paths filtrado para Projetos/Olist/Olist_DataEnginier/**
   environment: dev
   permissions: id-token: write, contents: read
   env: DATABRICKS_AUTH_TYPE=github-oidc, DATABRICKS_HOST, DATABRICKS_CLIENT_ID
     (client id via ${{ vars.DATABRICKS_CLIENT_ID }} — não é segredo, é o
     Application ID do service principal)
   steps: checkout → databricks/setup-cli@main → databricks bundle validate --target dev

2. .github/workflows/olist-deploy-dev.yml
   on: push para main, mesmo paths filter
   environment: dev
   mesma autenticação; roda databricks bundle deploy --target dev
   NÃO rode o job aqui — olist_pipeline já tem agendamento próprio diário.

3. .github/workflows/olist-deploy-prod.yml
   on: workflow_dispatch (só manual)
   environment: prod
   mesma autenticação; roda databricks bundle deploy --target prod
   Documente que o gate real de aprovação é o Required reviewer configurado
   no GitHub Environment "prod", não o gatilho em si.

Os workflows ficam na RAIZ do repositório (Documentos), não dentro da pasta
do projeto — é onde o GitHub exige. Confira que o .gitignore da raiz do
repositório libera .github/, senão os workflows nunca são versionados.

Isso não cria o Service Principal nem a política de federação — isso
acontece no console da CONTA Databricks, fora do bundle. Me dê o passo a
passo de:
  1. criar o service principal (console da conta)
  2. dar permissão dele no workspace e no catálogo lakehouse_olist
  3. o comando `databricks account service-principal-federation-policy create`
     para confiar no repo juliocbarros/olist-lakehouse
  4. criar os Environments dev/prod no GitHub, com required reviewer em prod
  5. registrar o Application ID como Environment variable DATABRICKS_CLIENT_ID
     nos dois Environments
```

---

## Como verificar a feature

**1 · Os três workflows existem e estão rastreados pelo git**

```bash
git status -s .github/
git check-ignore -v .github/workflows/*.yml   # não deve imprimir nada
```

**2 · O PR valida sozinho**

Abra um PR mudando qualquer arquivo em
`Projetos/Olist/Olist_DataEnginier/`. A aba **Checks** do PR deve mostrar
"Validar bundle" rodando, sem você ter tocado num terminal.

**3 · O push faz o dev se atualizar sozinho**

```sql
SELECT max(_processado_em) FROM lakehouse_olist.gold.dim_cliente;
```
Merge o PR, espere o workflow "Deploy dev" terminar em Actions, rode a
query de novo — o timestamp não muda sozinho (deploy não roda o pipeline),
mas `databricks bundle summary --target dev` deve refletir a versão nova
do bundle. Para ver o efeito ponta a ponta, dispare
`databricks bundle run olist_pipeline --target dev --profile Olist` depois
do deploy e compare o timestamp antes/depois.

**4 · O prod não roda sem alguém apertar o botão**

```bash
git log --oneline -1   # confirme que a main tem commit novo
```
Confira em **Actions** que só "Validar bundle" e "Deploy dev" dispararam.
"Deploy prod" deve aparecer como *não executado* até você ir manualmente
em Actions → Deploy prod → Run workflow — e, se o Environment "prod" tiver
required reviewer, o workflow fica **esperando aprovação** antes de rodar
qualquer step.

**5 · A prova de que não há segredo salvo — audite os secrets do repo**

```
GitHub → juliocbarros/olist-lakehouse → Settings → Secrets and variables → Actions
```
Não deve existir nenhum secret com token do Databricks. `DATABRICKS_CLIENT_ID`
aparece como **Variable**, não como **Secret** — porque um Application ID
sozinho, sem o par de federação aprovado, não autentica nada.

---

## Fala de aula

> *"Repara o que NÃO existe aqui: não tem senha em lugar nenhum. O GitHub
> assina um token que diz 'eu sou o workflow tal, do repo tal, do environment
> tal', e o Databricks decide se confia nisso — e essa decisão fica escrita
> numa política, não numa variável de ambiente que alguém esqueceu de
> girar há oito meses."*
>
> *"E o prod não é mais rápido só porque é manual — é mais seguro porque o
> gate de aprovação mora no GitHub, não na memória de quem lembrou (ou não)
> de rodar o comando certo no terminal certo."*

---

## Se der errado ao vivo

| Sintoma | Causa | Correção em um prompt |
|---|---|---|
| Workflow nem aparece na aba Actions | `.github/workflows/*.yml` está sendo ignorado pelo `.gitignore` da raiz | *"Adicione `!/.github` no `.gitignore` da raiz do repositório."* |
| `Error: unable to exchange token` no step do CLI | Política de federação não bate com repo/environment do token | Confira `subject` da política: precisa ser exatamente `repo:juliocbarros/olist-lakehouse:environment:<dev ou prod>` |
| Token emitido mas Databricks recusa | Faltou `permissions: id-token: write` no workflow YAML | Adicione o bloco `permissions` no nível do job (ou do workflow) |
| `PERMISSION_DENIED` ao rodar `bundle deploy` | Service principal não tem grant no catálogo/schema | Rode os `GRANT` de `USE CATALOG`/`USE SCHEMA`/`CREATE TABLE` para o Application ID do SP em `lakehouse_olist` |
| "Deploy prod" roda sem pedir aprovação | Environment "prod" no GitHub não tem Required reviewers configurado | Settings → Environments → prod → Required reviewers → adicione um revisor |
| `DATABRICKS_CLIENT_ID` vazio no log | Variável foi criada como **Secret** em vez de **Environment variable**, ou no Environment errado | Recrie em Settings → Environments → *o environment certo* → Variables |

**Tempo medido:** ~20s por execução do "Validar bundle", ~40s por deploy (dev ou prod).
