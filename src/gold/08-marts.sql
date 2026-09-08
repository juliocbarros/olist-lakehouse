-- Gold: marts de consumo — leem só de gold.fato_vendas + dimensões,
-- nunca de silver ou bronze.

CREATE OR REPLACE TABLE lakehouse_olist.gold.mart_vendas_mensal
COMMENT 'Receita, pedidos e ticket médio por ano/mês, só pedidos não cancelados.'
AS
SELECT
  year(f.data_compra) AS ano,
  month(f.data_compra) AS mes,
  COUNT(DISTINCT f.pedido_id) AS total_pedidos,
  SUM(f.receita) AS receita,
  ROUND(SUM(f.receita) / NULLIF(COUNT(DISTINCT f.pedido_id), 0), 2) AS ticket_medio,
  ROUND(AVG(f.tempo_entrega_dias), 1) AS tempo_entrega_medio_dias
FROM lakehouse_olist.gold.fato_vendas f
WHERE NOT f.cancelado
GROUP BY year(f.data_compra), month(f.data_compra);

CREATE OR REPLACE TABLE lakehouse_olist.gold.mart_categoria_performance
COMMENT 'Receita e volume por categoria de produto, só pedidos não cancelados.'
AS
SELECT
  coalesce(d.categoria_en, 'sem_categoria') AS categoria_en,
  COUNT(*) AS itens_vendidos,
  COUNT(DISTINCT f.pedido_id) AS pedidos,
  SUM(f.receita) AS receita,
  ROUND(AVG(f.nota_avaliacao), 2) AS nota_media
FROM lakehouse_olist.gold.fato_vendas f
LEFT JOIN lakehouse_olist.gold.dim_produto d ON d.product_id = f.produto_id
WHERE NOT f.cancelado
GROUP BY coalesce(d.categoria_en, 'sem_categoria');

CREATE OR REPLACE TABLE lakehouse_olist.gold.mart_vendedor_performance
COMMENT 'Receita, volume e prazo de entrega por vendedor, só pedidos não cancelados.'
AS
SELECT
  f.vendedor_id,
  v.cidade,
  v.uf,
  COUNT(*) AS itens_vendidos,
  COUNT(DISTINCT f.pedido_id) AS pedidos,
  SUM(f.receita) AS receita,
  ROUND(AVG(f.atraso_dias), 1) AS atraso_medio_dias,
  ROUND(AVG(f.nota_avaliacao), 2) AS nota_media
FROM lakehouse_olist.gold.fato_vendas f
LEFT JOIN lakehouse_olist.gold.dim_vendedor v ON v.seller_id = f.vendedor_id
WHERE NOT f.cancelado
GROUP BY f.vendedor_id, v.cidade, v.uf;

CREATE OR REPLACE TABLE lakehouse_olist.gold.mart_geografia
COMMENT 'Receita, pedidos e clientes únicos por UF do cliente, só pedidos não cancelados.'
AS
SELECT
  c.uf,
  COUNT(DISTINCT f.cliente_id) AS clientes_unicos,
  COUNT(DISTINCT f.pedido_id) AS pedidos,
  SUM(f.receita) AS receita
FROM lakehouse_olist.gold.fato_vendas f
JOIN lakehouse_olist.gold.dim_cliente c ON c.customer_unique_id = f.cliente_id
WHERE NOT f.cancelado
GROUP BY c.uf;
