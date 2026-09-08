# olist

Databricks Asset Bundle with a medallion pipeline (raw → bronze → silver →
gold) over the public **Brazilian E-Commerce (Olist)** dataset, modeled
after the `rotaperfume` project architecture.

## Architecture

```
Volume bronze.raw (9 CSVs)
        │
        ▼
src/raw/conferencia.py        checks that all 9 files arrived
        │
        ▼
src/bronze/ingestao.py        writes the 9 CSVs as Delta, everything STRING
        │
        ▼
src/silver/*.sql              cleaning, typing, deduplication
  01-clientes.sql
  02-pedidos.sql
  03-produtos-vendedores.sql
  04-itens-pagamentos-avaliacoes.sql
  05-geolocalizacao.sql
        │
        ▼
src/gold/*.sql                dimensions → fact → marts → tests → metrics
  06-dimensoes.sql            (dim_cliente, dim_produto, dim_vendedor,
                                dim_geografia, dim_calendario)
  07-fato-vendas.sql          (grain: order item)
  08-marts.sql                (monthly sales, category, seller, geography)
  09-testes.sql                9 quality tests — breaks the job on failure
  10-metricas-negocio.sql     views for dashboard/Genie
```

Orchestrated by the `olist_pipeline` job in `resources/pipeline.job.yml`.

## Catalog

- **catalog**: `lakehouse_olist`
- **schemas**: `bronze`, `silver`, `gold`
- **volume**: `bronze.raw` (CSV landing zone)

The catalog is created outside the bundle via `scripts/criar-catalogo.sh`
(see the comment in the script for why). Schemas and volume are created by
the bundle, in `resources/catalogo.yml`.

## Important Olist dataset quirk

`customer_id` is generated per **order**, not per person — the same real
customer gets a new `customer_id` on every purchase. `customer_unique_id`
is what identifies the person. That's why `gold.dim_cliente` is grained on
`customer_unique_id`, aggregating the history of every `customer_id`
belonging to the same person (see the comment in `silver/01-clientes.sql`).

## How to run

```bash
# 1. Authenticate (once)
databricks auth login --host https://dbc-604bc86c-0b09.cloud.databricks.com --profile <profile>

# 2. Create the catalog (once, outside the bundle)
scripts/criar-catalogo.sh <profile>

# 3. Deploy the bundle (creates schemas, volume, notebooks and the job)
databricks bundle deploy --target dev --profile <profile>

# 4. Upload the 9 CSVs to the bronze.raw Volume
scripts/subir-raw.sh <profile>

# 5. Run the full pipeline
databricks bundle run olist_pipeline --target dev --profile <profile>
```

## Data source

Public dataset "Brazilian E-Commerce Public Dataset by Olist" — 9 CSVs:
customers, geolocation, orders, order_items, order_payments,
order_reviews, products, sellers, product_category_name_translation.
