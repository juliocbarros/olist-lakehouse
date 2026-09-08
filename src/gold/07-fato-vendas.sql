-- Gold: fato_vendas no grão de item de pedido (uma linha por
-- pedido_id + item_id). Pagamento e avaliação são por pedido, não por
-- item — o valor/nota do pedido é repetido em cada item dele, de propósito
-- (evita fan-out incorreto: nunca somamos valor_pago por engano ao agrupar
-- por item).

CREATE OR REPLACE TABLE lakehouse_olist.gold.fato_vendas
COMMENT 'Fato no grão de item de pedido. receita = preco + frete do item; valor_pago/nota_avaliacao são do pedido inteiro, repetidos por item.'
AS
WITH pagamento_pedido AS (
  -- forma de pagamento "principal" = primeira usada (sequencial = 1);
  -- valor_pago = soma de todas as parcelas/formas do pedido
  SELECT
    order_id,
    SUM(valor_pagamento) AS valor_pago,
    max_by(tipo_pagamento, -sequencial) AS metodo_pagamento_principal
  FROM lakehouse_olist.silver.pagamentos
  GROUP BY order_id
),
avaliacao_pedido AS (
  SELECT order_id, avg(nota) AS nota_media, count(*) AS qtd_avaliacoes
  FROM lakehouse_olist.silver.avaliacoes
  GROUP BY order_id
)
SELECT
  i.order_id AS pedido_id,
  i.item_id,
  p.customer_id,
  c.customer_unique_id AS cliente_id,
  i.product_id AS produto_id,
  i.seller_id AS vendedor_id,
  p.data_compra,
  p.status,
  p.cancelado,
  p.entregue,
  p.tempo_entrega_dias,
  p.atraso_dias,
  i.preco,
  i.frete,
  i.valor_item AS receita,
  pp.valor_pago,
  pp.metodo_pagamento_principal,
  av.nota_media AS nota_avaliacao,
  current_timestamp() AS _processado_em
FROM lakehouse_olist.silver.itens_pedido i
JOIN lakehouse_olist.silver.pedidos p ON p.order_id = i.order_id
JOIN lakehouse_olist.silver.clientes c ON c.customer_id = p.customer_id
LEFT JOIN pagamento_pedido pp ON pp.order_id = i.order_id
LEFT JOIN avaliacao_pedido av ON av.order_id = i.order_id;

COMMENT ON COLUMN lakehouse_olist.gold.fato_vendas.receita IS
  'preco + frete deste item específico. Soma por pedido_id para reconstruir o valor do pedido.';
COMMENT ON COLUMN lakehouse_olist.gold.fato_vendas.valor_pago IS
  'Soma de TODAS as parcelas/formas de pagamento do pedido — repetido em cada item; não somar ao agrupar por item sem antes deduplicar por pedido_id.';

ALTER TABLE lakehouse_olist.gold.fato_vendas
  ADD CONSTRAINT grao_item_unico CHECK (pedido_id IS NOT NULL AND item_id IS NOT NULL);
