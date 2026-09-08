# Databricks notebook source
# MAGIC %md
# MAGIC # Conferência de chegada — raw
# MAGIC Confere que os 9 arquivos esperados do dataset Olist chegaram ao
# MAGIC Volume `bronze.raw`, registra tamanho/linhas em
# MAGIC `bronze._raw_arquivos` e falha o job se algum arquivo estiver
# MAGIC faltando ou vazio.

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_olist")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------

from datetime import datetime, timezone

# (arquivo_csv_na_origem, tabela_bronze_destino)
ARQUIVOS_ESPERADOS = [
    ("olist_customers_dataset", "customers"),
    ("olist_geolocation_dataset", "geolocation"),
    ("olist_orders_dataset", "orders"),
    ("olist_order_items_dataset", "order_items"),
    ("olist_order_payments_dataset", "order_payments"),
    ("olist_order_reviews_dataset", "order_reviews"),
    ("olist_products_dataset", "products"),
    ("olist_sellers_dataset", "sellers"),
    ("product_category_name_translation", "product_category_translation"),
]

volume_base = f"/Volumes/{catalog}/bronze/raw"

# COMMAND ----------

resultados = []
faltando = []
vazios = []

for arquivo, tabela in ARQUIVOS_ESPERADOS:
    caminho = f"{volume_base}/{arquivo}.csv"
    try:
        info = dbutils.fs.ls(caminho)[0]
    except Exception:
        faltando.append(caminho)
        continue

    # multiLine=true é necessário aqui pelo mesmo motivo da ingestão bronze:
    # review_comment_message tem quebras de linha dentro do campo entre
    # aspas, e sem essa opção a contagem de linhas fica errada (maior que o
    # número real de registros) porque cada comentário multilinha é
    # contado como se fossem várias linhas.
    df = (
        spark.read.option("header", "true")
        .option("multiLine", "true")
        .option("quote", '"')
        .option("escape", '"')
        .csv(caminho)
    )
    linhas = df.count()
    if linhas == 0:
        vazios.append(caminho)

    resultados.append(
        {
            "tabela": tabela,
            "arquivo": f"{arquivo}.csv",
            "bytes": info.size,
            "linhas": linhas,
            "conferido_em": datetime.now(timezone.utc),
        }
    )

if faltando or vazios:
    detalhes = []
    if faltando:
        detalhes.append(f"faltando: {', '.join(faltando)}")
    if vazios:
        detalhes.append(f"vazios: {', '.join(vazios)}")
    raise Exception("Conferência de chegada falhou — " + "; ".join(detalhes))

# COMMAND ----------

spark.sql(f"USE CATALOG `{catalog}`")

spark.sql(
    """
    CREATE TABLE IF NOT EXISTS bronze._raw_arquivos (
        tabela STRING,
        arquivo STRING,
        bytes BIGINT,
        linhas BIGINT,
        conferido_em TIMESTAMP
    )
    COMMENT 'Registro de conferência de chegada dos arquivos raw a cada execução do pipeline.'
    """
)

df_resultados = spark.createDataFrame(resultados)
df_resultados.write.mode("append").saveAsTable("bronze._raw_arquivos")

# COMMAND ----------

print(f"{'tabela':<26} {'arquivo':<38} {'bytes':>10} {'linhas':>10}")
for r in resultados:
    print(f"{r['tabela']:<26} {r['arquivo']:<38} {r['bytes']:>10} {r['linhas']:>10}")

print(f"\n{len(resultados)} arquivos conferidos com sucesso.")
