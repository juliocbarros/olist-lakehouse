# Prompt 1 · Lakehouse Olist — do zero ao pipeline medalhão completo

**Entrega:** o bundle existe, o catálogo inteiro é código, os 9 CSVs da Olist
saem do Volume raw e chegam a gold como fato de vendas, dimensões, marts e
métricas de negócio, com 9 testes de qualidade travando o job se algo quebrar.
**Deploy nº 1.**

> **O momento "agora entendi".** O scaffold do `databricks bundle init` te dá
> uma pasta vazia com um notebook de exemplo de táxi de Nova York. Hoje ela
> vira um lakehouse de verdade, com a mesma arquitetura (raw → bronze → silver
> → gold) usada no projeto de perfumes — só que modelada em cima de um dataset
> público de e-commerce, com as pegadinhas que ele traz.

---

## O que mostrar antes

Abra o Catalog Explorer e o VS Code lado a lado, antes de colar o prompt.

```bash
# 1. o catálogo da Olist não existe
databricks catalogs list --profile Olist | grep lakehouse_olist || echo 'não existe'

# 2. os 9 CSVs existem, mas só no seu computador
ls -1 "C:/Users/julio/OneDrive/Documentos/Dados & Analytics/Base de teste/Base_Olist/Olist_new"
```

```sql
-- 3. a prova de que não há nada no workspace ainda
SELECT COUNT(*) FROM lakehouse_olist.bronze.customers;
-- [TABLE_OR_VIEW_NOT_FOUND] · Catalog 'lakehouse_olist' was not found
```

**A pergunta para quem for revisar isso depois:** *"o projeto que o
`databricks bundle init` te deu tem um notebook de exemplo de táxi. Quanto do
que muda daqui pra um pipeline de verdade é reescrever tudo, e quanto é só
trocar o que é específico do domínio (as tabelas, as regras de negócio) em
cima da mesma espinha dorsal?"*

---

**Enquanto ele trabalha, você explica:**

- **Raw não é bronze.** Raw é *arquivo* (CSV cru no Volume); bronze é *tabela*
  Delta, ainda sem tipo, sem limpeza — só uma cópia fiel com timestamp de
  ingestão. Silver é onde o dado ganha tipo e regra de negócio. Gold é o que
  o dashboard e o Genie realmente consultam.
- **A pegadinha do dataset Olist:** `customer_id` é gerado por *pedido*, não
  por pessoa — o mesmo cliente ganha um ID novo a cada compra.
  `customer_unique_id` é quem identifica a pessoa de fato. Ignorar isso faz a
  dimensão de cliente contar "clientes novos" que são, na verdade, a mesma
  pessoa comprando de novo — o equivalente ao problema de CNPJ duplicado do
  projeto de perfumes.
- **Por que geolocation vira uma agregação, não uma cópia.** A tabela bronze
  de geolocalização tem mais de 1 milhão de linhas — várias coordenadas por
  CEP-prefixo. A silver agrega isso a um ponto médio por CEP antes de virar
  dimensão; copiar 1M de linhas para uma dimensão de "CEP" seria carregar
  ruído geocodificado como se fosse grão de negócio.
- **Testes que quebram o job de propósito.** Teste que não derruba a tarefa
  não é teste, é relatório. Os 9 testes da gold (receita batendo entre
  camadas, órfãos, nota de 1 a 5, volume dentro do esperado) usam
  `raise_error` para parar o pipeline se algo não bater.

---

## O prompt

```
Leia o README.md deste projeto antes de começar.

Crie o pipeline completo em C:\Users\julio\...\Olist_DataEnginier, um
Databricks Asset Bundle já inicializado pelo `databricks bundle init`
(template default-python) e conectado ao VS Code — remova o scaffold de
exemplo (my_project_etl, taxis.py, sample_job.job.yml) e construa por cima.

CONTEXTO DO WORKSPACE
- profile: Olist              (sempre passe --profile, nunca deixe implícito)
- host: https://dbc-604bc86c-0b09.cloud.databricks.com
- SQL Warehouse: 7c3ea71f9ae30d85
- catalog: lakehouse_olist
- Os 9 CSVs do dataset público "Brazilian E-Commerce (Olist)" estão em
  C:\Users\julio\...\Base_Olist\Olist_new — sem subpastas por sistema (é uma
  fonte só, ao contrário do erp/crm do projeto de perfumes).

1. databricks.yml
   - bundle name: olist
   - variables: catalog (default lakehouse_olist) e warehouse_id
     (default 7c3ea71f9ae30d85)
   - targets dev (default) e prod

   MESMA ARMADILHA DO ROTAPERFUME: NÃO use `mode: development` no target dev
   — ele prefixaria os schemas do Unity Catalog e quebraria todo o SQL que
   referencia lakehouse_olist.bronze.*. Pause o agendamento explicitamente
   com `presets: { trigger_pause_status: PAUSED }`.

2. scripts/criar-catalogo.sh + resources/catalogo.yml
   Catálogo criado fora do bundle via SQL (mesma limitação de metastore do
   projeto de perfumes). Dentro do bundle: schemas bronze/silver/gold e o
   Volume bronze.raw, do tipo MANAGED, com COMMENT explicando cada camada.

3. scripts/subir-raw.sh
   Sobe os 9 CSVs (achatados, sem subpasta) para /Volumes/lakehouse_olist/bronze/raw.
   Receba a pasta de origem como argumento, com default para o caminho acima
   — ela não fica dentro do repositório do bundle.

4. src/raw/conferencia.py
   Confere a chegada dos 9 arquivos esperados: customers, geolocation,
   orders, order_items, order_payments, order_reviews, products, sellers,
   product_category_name_translation. Grava bronze._raw_arquivos. Levanta
   exceção se faltar ou vier vazio.

5. src/bronze/ingestao.py
   Ingestão das 9 tabelas, tudo STRING, com _ingerido_em e _arquivo_origem.
   Confere contagem contra bronze._raw_arquivos ao final.

6. src/silver/*.sql — cinco arquivos
   01-clientes: tipagem + normalização de CEP/cidade/UF. Documente a
     diferença customer_id vs customer_unique_id.
   02-pedidos: datas do ciclo completo (compra, aprovação, envio, entrega,
     estimativa), cancelado/entregue, tempo_entrega_dias, atraso_dias.
   03-produtos-vendedores: produtos com categoria traduzida via
     product_category_name_translation; vendedores com localização tipada.
   04-itens-pagamentos-avaliacoes: itens de pedido (preço+frete), pagamentos
     (podem ter várias linhas por pedido) e avaliações (dedup por review_id).
   05-geolocalizacao: agrega bronze.geolocation por CEP-prefixo em um ponto
     médio de lat/lng — não copie 1M de linhas cruas para a silver.

7. src/gold/*.sql — cinco arquivos
   06-dimensoes: dim_cliente (grão customer_unique_id, resolvendo os vários
     customer_id da mesma pessoa), dim_produto, dim_vendedor, dim_geografia,
     dim_calendario (com flag de meses de pico do varejo brasileiro: maio,
     agosto, novembro, dezembro).
   07-fato-vendas: grão de item de pedido. Pagamento e avaliação são por
     pedido — documente que valor_pago é repetido por item e não deve ser
     somado sem deduplicar por pedido antes.
   08-marts: vendas mensais, performance por categoria, por vendedor, por
     geografia — todos só com pedidos não cancelados.
   09-testes: 9 testes que batem receita entre camadas, órfãos de pedido/
     cliente, nota entre 1 e 5, volume esperado de linhas, soma dos marts
     batendo com o fato. Derrube o job com raise_error se algum falhar.
   10-metricas-negocio: views para dashboard/Genie — KPIs gerais, taxa de
     cancelamento por mês, distribuição por método de pagamento, top 10
     categorias.

8. resources/pipeline.job.yml
   Job olist_pipeline: raw_conferencia → bronze_ingestao → 5 tarefas silver
   em paralelo → gold_dimensoes → gold_fato_vendas → gold_marts → (testes e
   metricas_de_negocio em paralelo). Agendamento diário às 6h,
   America/Sao_Paulo.

9. Valide antes de rodar:
   databricks bundle validate --target dev --profile Olist

   Se aparecer "no files to sync", verifique se algum .gitignore num nível
   acima do projeto (ex.: um repositório git na raiz de Documentos) está
   excluindo a pasta inteira — foi o que aconteceu aqui.

10. Rode nesta ordem e me mostre a saída de cada passo:
    scripts/criar-catalogo.sh Olist
    databricks bundle deploy --target dev --profile Olist
    scripts/subir-raw.sh Olist
    databricks bundle run olist_pipeline --target dev --profile Olist
```

---

## Como verificar a feature

**1 · O catálogo inteiro existe, e nasceu de YAML**

```sql
SHOW SCHEMAS IN lakehouse_olist;                -- bronze, silver, gold
DESCRIBE VOLUME lakehouse_olist.bronze.raw;
```

**2 · Os 9 arquivos chegaram ao Volume**

```sql
LIST '/Volumes/lakehouse_olist/bronze/raw';
```

**3 · A conferência de chegada registrou o que chegou**

```sql
SELECT tabela, arquivo, bytes, linhas, conferido_em
FROM lakehouse_olist.bronze._raw_arquivos
ORDER BY linhas DESC;
```

| Tabela | Linhas esperadas (dataset público Olist) |
|---|---|
| order_items | ~112.650 |
| order_payments | ~103.886 |
| orders | ~99.441 |
| customers | ~99.441 |
| order_reviews | ~99.224 |
| products | ~32.951 |
| sellers | ~3.095 |
| product_category_translation | ~71 |
| geolocation | ~1.000.163 |

> Valores de referência do dataset público — confirme os números reais do
> seu arquivo com a query acima, pode haver pequenas diferenças de versão.

**4 · A fato_vendas bate com a silver**

```sql
SELECT ROUND(SUM(receita), 2) FROM lakehouse_olist.gold.fato_vendas;
SELECT ROUND(SUM(valor_item), 2) FROM lakehouse_olist.silver.itens_pedido;
-- os dois números devem ser idênticos
```

**5 · Os 9 testes passam**

```bash
databricks bundle run olist_pipeline --target dev --profile Olist
```
A tarefa `testes` deve terminar com `TODOS OS 9 TESTES PASSARAM`.

**6 · A prova de que é código, não clique — apague e traga de volta**

```sql
DROP SCHEMA lakehouse_olist.gold CASCADE;
SHOW SCHEMAS IN lakehouse_olist;                -- gold sumiu
```
```bash
databricks bundle deploy --target dev --profile Olist
databricks bundle run olist_pipeline --target dev --profile Olist
```

**7 · A prova de que a conferência serve para algo — quebre de propósito**

```bash
databricks fs rm dbfs:/Volumes/lakehouse_olist/bronze/raw/olist_order_reviews_dataset.csv --profile Olist
databricks bundle run olist_pipeline --target dev --profile Olist
# raw_conferencia FALHA e o job para: falta order_reviews
scripts/subir-raw.sh Olist     # devolve o arquivo e roda de novo
```

---

## Fala de aula

> *"O scaffold que o `bundle init` gerou tinha um notebook de exemplo de táxi
> de Nova York. Trocamos o domínio inteiro — 9 tabelas de e-commerce, uma
> pegadinha de cliente duplicado, geolocalização que precisa de agregação — e
> a espinha dorsal (raw → bronze → silver → gold, testes que derrubam o job)
> não mudou uma linha. É esse o valor de ter um padrão: o que muda de projeto
> pra projeto é o domínio, não a arquitetura."*
>
> *"E repara: `customer_id` não é a pessoa, é o pedido. Se a dim_cliente
> agregasse por `customer_id`, todo cliente recorrente apareceria como vários
> clientes novos — a receita por cliente ficaria certa na soma, mas a métrica
> de recorrência mentiria."*

---

## Se der errado ao vivo

| Sintoma | Causa | Correção em um prompt |
|---|---|---|
| `Metastore storage root URL does not exist` no deploy | O bundle tentou criar o catálogo pela API | *"Tire o catálogo do bundle e crie por SQL num script."* |
| Os schemas viraram `dev_seunome_bronze` | `mode: development` no target dev | *"Tire o `mode: development` e pause o agendamento com `presets: trigger_pause_status: PAUSED`."* |
| `there are no files to sync` no validate | Um `.gitignore` num nível acima (ex.: raiz de Documentos) exclui a pasta inteira do projeto | Adicione a exceção `!/Projetos/<pasta-do-projeto>` no `.gitignore` de nível superior |
| `multiple profiles matched` | Vários profiles do CLI apontam para o mesmo host | Passe `--profile Olist` explicitamente em todo comando |
| Contagem de `dim_cliente` maior que o esperado | Agregou por `customer_id` em vez de `customer_unique_id` | Refaça o join de resolução de cliente único antes de agregar |
| `databricks fs cp` reclama do caminho | Faltou o esquema `dbfs:` no destino | O destino é `dbfs:/Volumes/...`, mesmo sendo Volume do UC |

**Tempo medido:** ~1min de deploy, ~1min de upload dos 9 CSVs (o geolocation é o mais pesado), ~2-3min de execução do pipeline completo.
