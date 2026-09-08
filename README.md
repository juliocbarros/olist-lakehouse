# olist

Databricks Asset Bundle com um pipeline medalhão (raw → bronze → silver →
gold) sobre o dataset público **Brazilian E-Commerce (Olist)**, modelado a
partir da arquitetura do projeto `rotaperfume`.

## Arquitetura

```
Volume bronze.raw (9 CSVs)
        │
        ▼
src/raw/conferencia.py        confere chegada dos 9 arquivos
        │
        ▼
src/bronze/ingestao.py        grava os 9 CSVs como Delta, tudo STRING
        │
        ▼
src/silver/*.sql              limpeza, tipagem, deduplicação
  01-clientes.sql
  02-pedidos.sql
  03-produtos-vendedores.sql
  04-itens-pagamentos-avaliacoes.sql
  05-geolocalizacao.sql
        │
        ▼
src/gold/*.sql                dimensões → fato → marts → testes → métricas
  06-dimensoes.sql            (dim_cliente, dim_produto, dim_vendedor,
                                dim_geografia, dim_calendario)
  07-fato-vendas.sql          (grão: item de pedido)
  08-marts.sql                (vendas mensais, categoria, vendedor, geografia)
  09-testes.sql                9 testes de qualidade — quebra o job se falhar
  10-metricas-negocio.sql     views para dashboard/Genie
```

Orquestrado pelo job `olist_pipeline` em `resources/pipeline.job.yml`.

## Catálogo

- **catalog**: `lakehouse_olist`
- **schemas**: `bronze`, `silver`, `gold`
- **volume**: `bronze.raw` (landing zone dos CSVs)

O catálogo é criado fora do bundle via `scripts/criar-catalogo.sh` (ver
comentário no script para o motivo). Schemas e volume são criados pelo
bundle, em `resources/catalogo.yml`.

## Quirk importante do dataset Olist

`customer_id` é gerado por **pedido**, não por pessoa — o mesmo cliente
real ganha um `customer_id` novo a cada compra. Quem identifica a pessoa é
`customer_unique_id`. Por isso `gold.dim_cliente` tem grão de
`customer_unique_id`, agregando o histórico de todos os `customer_id` da
mesma pessoa (ver comentário em `silver/01-clientes.sql`).

## Como rodar

```bash
# 1. Autenticar (uma vez)
databricks auth login --host https://dbc-604bc86c-0b09.cloud.databricks.com --profile <profile>

# 2. Criar o catálogo (uma vez, fora do bundle)
scripts/criar-catalogo.sh <profile>

# 3. Deploy do bundle (cria schemas, volume, notebooks e o job)
databricks bundle deploy --target dev --profile <profile>

# 4. Subir os 9 CSVs para o Volume bronze.raw
scripts/subir-raw.sh <profile>

# 5. Rodar o pipeline completo
databricks bundle run olist_pipeline --target dev --profile <profile>
```

## Fonte dos dados

Dataset público "Brazilian E-Commerce Public Dataset by Olist" — 9 CSVs:
customers, geolocation, orders, order_items, order_payments,
order_reviews, products, sellers, product_category_name_translation.
