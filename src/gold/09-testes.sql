-- Gold: 9 testes de qualidade. Se qualquer um falhar, a tarefa (e o job)
-- para — teste que não quebra o job não é teste, é relatório.

CREATE OR REPLACE TEMPORARY VIEW _resultados_testes AS
SELECT
  'receita_gold_igual_silver' AS teste,
  CAST(ROUND((SELECT SUM(receita) FROM lakehouse_olist.gold.fato_vendas), 2) AS STRING) AS valor,
  CAST(ROUND((SELECT SUM(valor_item) FROM lakehouse_olist.silver.itens_pedido), 2) AS STRING) AS esperado,
  abs(
    (SELECT SUM(receita) FROM lakehouse_olist.gold.fato_vendas)
    - (SELECT SUM(valor_item) FROM lakehouse_olist.silver.itens_pedido)
  ) <= 0.01 AS passou

UNION ALL
SELECT
  'sem_item_orfao_de_pedido',
  CAST((
    SELECT COUNT(*) FROM lakehouse_olist.gold.fato_vendas f
    LEFT ANTI JOIN lakehouse_olist.silver.pedidos p ON p.order_id = f.pedido_id
  ) AS STRING),
  '0',
  (
    SELECT COUNT(*) FROM lakehouse_olist.gold.fato_vendas f
    LEFT ANTI JOIN lakehouse_olist.silver.pedidos p ON p.order_id = f.pedido_id
  ) = 0

UNION ALL
SELECT
  'sem_item_orfao_de_cliente',
  CAST((
    SELECT COUNT(*) FROM lakehouse_olist.gold.fato_vendas f
    LEFT ANTI JOIN lakehouse_olist.gold.dim_cliente c ON c.customer_unique_id = f.cliente_id
  ) AS STRING),
  '0',
  (
    SELECT COUNT(*) FROM lakehouse_olist.gold.fato_vendas f
    LEFT ANTI JOIN lakehouse_olist.gold.dim_cliente c ON c.customer_unique_id = f.cliente_id
  ) = 0

UNION ALL
SELECT
  'data_compra_nao_nula',
  CAST((SELECT COUNT(*) FROM lakehouse_olist.silver.pedidos WHERE data_compra IS NULL) AS STRING),
  '0',
  (SELECT COUNT(*) FROM lakehouse_olist.silver.pedidos WHERE data_compra IS NULL) = 0

UNION ALL
SELECT
  'nota_avaliacao_entre_1_e_5',
  CAST((
    SELECT COUNT(*) FROM lakehouse_olist.gold.fato_vendas
    WHERE nota_avaliacao IS NOT NULL AND nota_avaliacao NOT BETWEEN 1 AND 5
  ) AS STRING),
  '0',
  (
    SELECT COUNT(*) FROM lakehouse_olist.gold.fato_vendas
    WHERE nota_avaliacao IS NOT NULL AND nota_avaliacao NOT BETWEEN 1 AND 5
  ) = 0

UNION ALL
SELECT
  'volume_fato_vendas',
  CAST((SELECT COUNT(*) FROM lakehouse_olist.gold.fato_vendas) AS STRING),
  'entre 100000 e 120000',
  (SELECT COUNT(*) FROM lakehouse_olist.gold.fato_vendas) BETWEEN 100000 AND 120000

UNION ALL
SELECT
  'mart_categoria_soma_igual_fato',
  CAST(ROUND((SELECT SUM(receita) FROM lakehouse_olist.gold.mart_categoria_performance), 2) AS STRING),
  CAST(ROUND((SELECT SUM(receita) FROM lakehouse_olist.gold.fato_vendas WHERE NOT cancelado), 2) AS STRING),
  abs(
    (SELECT SUM(receita) FROM lakehouse_olist.gold.mart_categoria_performance)
    - (SELECT SUM(receita) FROM lakehouse_olist.gold.fato_vendas WHERE NOT cancelado)
  ) <= 0.01

UNION ALL
SELECT
  'mart_vendas_mensal_soma_igual_fato',
  CAST(ROUND((SELECT SUM(receita) FROM lakehouse_olist.gold.mart_vendas_mensal), 2) AS STRING),
  CAST(ROUND((SELECT SUM(receita) FROM lakehouse_olist.gold.fato_vendas WHERE NOT cancelado), 2) AS STRING),
  abs(
    (SELECT SUM(receita) FROM lakehouse_olist.gold.mart_vendas_mensal)
    - (SELECT SUM(receita) FROM lakehouse_olist.gold.fato_vendas WHERE NOT cancelado)
  ) <= 0.01

UNION ALL
SELECT
  'cep_prefixo_5_digitos_dim_geografia',
  CAST((SELECT COUNT(*) FROM lakehouse_olist.gold.dim_geografia WHERE length(cep_prefixo) <> 5) AS STRING),
  '0',
  (SELECT COUNT(*) FROM lakehouse_olist.gold.dim_geografia WHERE length(cep_prefixo) <> 5) = 0;

-- imprime nome, valor calculado, valor esperado e passou/falhou de cada teste
SELECT teste, valor, esperado, passou FROM _resultados_testes ORDER BY teste;

-- interrompe a tarefa (e o job) se qualquer teste falhou
SELECT
  CASE
    WHEN (SELECT COUNT(*) FROM _resultados_testes WHERE NOT passou) = 0
      THEN 'TODOS OS 9 TESTES PASSARAM'
    ELSE raise_error((
      SELECT concat('teste(s) falharam: ', concat_ws(', ', collect_list(teste)))
      FROM _resultados_testes
      WHERE NOT passou
    ))
  END AS resultado_final;
