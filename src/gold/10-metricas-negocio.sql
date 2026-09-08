-- Gold: views de métricas de negócio, consumidas por dashboards/Genie.
-- Views (não tabelas materializadas) porque são leituras leves sobre a
-- gold já pronta — não precisam de refresh próprio.

CREATE OR REPLACE VIEW lakehouse_olist.gold.vw_metricas_gerais
COMMENT 'Um único snapshot com os KPIs centrais do negócio, só pedidos não cancelados.'
AS
SELECT
  COUNT(DISTINCT pedido_id) AS total_pedidos,
  COUNT(DISTINCT cliente_id) AS total_clientes,
  SUM(receita) AS gmv,
  ROUND(SUM(receita) / NULLIF(COUNT(DISTINCT pedido_id), 0), 2) AS ticket_medio,
  ROUND(AVG(nota_avaliacao), 2) AS nota_media,
  ROUND(AVG(tempo_entrega_dias), 1) AS tempo_entrega_medio_dias,
  ROUND(AVG(atraso_dias), 1) AS atraso_medio_dias
FROM lakehouse_olist.gold.fato_vendas
WHERE NOT cancelado;

CREATE OR REPLACE VIEW lakehouse_olist.gold.vw_taxa_cancelamento
COMMENT 'Taxa de cancelamento por ano/mês, no grão de pedido (não de item).'
AS
WITH pedido_status AS (
  SELECT DISTINCT pedido_id, data_compra, cancelado
  FROM lakehouse_olist.gold.fato_vendas
)
SELECT
  year(data_compra) AS ano,
  month(data_compra) AS mes,
  COUNT(*) AS total_pedidos,
  SUM(CASE WHEN cancelado THEN 1 ELSE 0 END) AS pedidos_cancelados,
  ROUND(100.0 * SUM(CASE WHEN cancelado THEN 1 ELSE 0 END) / COUNT(*), 2) AS taxa_cancelamento_pct
FROM pedido_status
GROUP BY year(data_compra), month(data_compra);

CREATE OR REPLACE VIEW lakehouse_olist.gold.vw_metodo_pagamento
COMMENT 'Distribuição de pedidos e receita por método de pagamento principal, só pedidos não cancelados.'
AS
WITH pedido_pagamento AS (
  SELECT DISTINCT pedido_id, receita, metodo_pagamento_principal, valor_pago
  FROM lakehouse_olist.gold.fato_vendas
  WHERE NOT cancelado
)
SELECT
  coalesce(metodo_pagamento_principal, 'nao_informado') AS metodo_pagamento,
  COUNT(*) AS total_pedidos,
  SUM(valor_pago) AS valor_total_pago
FROM pedido_pagamento
GROUP BY coalesce(metodo_pagamento_principal, 'nao_informado');

CREATE OR REPLACE VIEW lakehouse_olist.gold.vw_top10_categorias
COMMENT 'As 10 categorias de produto com maior receita, só pedidos não cancelados.'
AS
SELECT categoria_en, itens_vendidos, pedidos, receita, nota_media
FROM lakehouse_olist.gold.mart_categoria_performance
ORDER BY receita DESC
LIMIT 10;
