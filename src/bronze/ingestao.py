# Databricks notebook source
# MAGIC %md
# MAGIC # Ingestão bronze — nove tabelas em um comando
# MAGIC Lê os 9 CSVs do Volume `bronze.raw`, grava cada um em Delta em
# MAGIC `bronze.{tabela}` sem nenhuma limpeza ou conversão de tipo — tudo
# MAGIC entra como STRING, de propósito. A sujeira da origem é preservada e
# MAGIC vira prova de auditoria; converter é trabalho da silver.

# COMMAND ----------

dbutils.widgets.text("catalog", "lakehouse_olist")
catalog = dbutils.widgets.get("catalog")

# COMMAND ----------

from pyspark.sql.functions import current_timestamp, lit

# (arquivo_csv_na_origem, tabela_bronze_destino)
TABELAS = [
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

spark.sql(f"USE CATALOG `{catalog}`")

# COMMAND ----------


def ingerir(arquivo, tabela):
    arquivo_origem = f"{arquivo}.csv"
    caminho = f"{volume_base}/{arquivo_origem}"

    # Tudo como STRING de propósito: sem inferSchema. Os CSVs da Olist têm
    # header e usam vírgula como separador padrão. multiLine=true é
    # obrigatório aqui: review_comment_message tem quebras de linha dentro
    # do campo entre aspas, e sem essa opção o Spark quebra a linha no meio
    # do comentário e desalinha as colunas seguintes (ex.: review_score
    # passa a conter uma data).
    df = (
        spark.read.option("header", "true")
        .option("multiLine", "true")
        .option("quote", '"')
        .option("escape", '"')
        .csv(caminho)
        .withColumn("_ingerido_em", current_timestamp())
        .withColumn("_arquivo_origem", lit(arquivo_origem))
    )

    # overwriteSchema: tabelas com esse nome podem já existir de fora do
    # bundle com um schema tipado. A bronze exige STRING em tudo, então o
    # schema é sempre substituído, não mesclado.
    df.write.mode("overwrite").option("overwriteSchema", "true").saveAsTable(f"bronze.{tabela}")

    spark.sql(
        f"COMMENT ON TABLE bronze.{tabela} IS "
        f"'Bronze — cópia bruta de {arquivo_origem}, sem limpeza nem conversão de tipo.'"
    )

    return spark.table(f"bronze.{tabela}").count()


# COMMAND ----------

contagens = []
for arquivo, tabela in TABELAS:
    linhas = ingerir(arquivo, tabela)
    contagens.append({"tabela": tabela, "linhas_bronze": linhas})

# COMMAND ----------

divergencias = []
resultado = []
for c in contagens:
    linhas_raw = spark.sql(
        f"SELECT linhas FROM bronze._raw_arquivos WHERE tabela = '{c['tabela']}' "
        f"ORDER BY conferido_em DESC LIMIT 1"
    ).collect()[0]["linhas"]

    bate = c["linhas_bronze"] == linhas_raw
    resultado.append({**c, "linhas_raw": linhas_raw, "bate": bate})
    if not bate:
        divergencias.append(c["tabela"])

# COMMAND ----------

print(f"{'tabela':<26} {'linhas_bronze':>14} {'linhas_raw':>12} {'bate':>6}")
for r in resultado:
    print(f"{r['tabela']:<26} {r['linhas_bronze']:>14} {r['linhas_raw']:>12} {str(r['bate']):>6}")

if divergencias:
    raise Exception(
        "Contagem divergente entre bronze e bronze._raw_arquivos: " + ", ".join(divergencias)
    )

print(f"\n{len(resultado)} tabelas ingeridas e conferidas com sucesso.")
