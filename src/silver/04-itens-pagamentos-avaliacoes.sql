-- Silver: itens de pedido, pagamentos e avaliações tipados.
-- Grão de cada tabela é diferente: itens_pedido é por item, pagamentos é
-- por parcela/forma de pagamento do pedido, avaliacoes é por review. Nenhum
-- dos três tem grão de pedido único — a fato_vendas na gold é quem
-- reconcilia isso.

CREATE OR REPLACE TABLE lakehouse_olist.silver.itens_pedido
COMMENT 'Silver — itens de pedido tipados; um item de um produto de um vendedor dentro de um pedido.'
AS
SELECT
  order_id,
  try_cast(order_item_id AS INT) AS item_id,
  product_id,
  seller_id,
  try_to_timestamp(shipping_limit_date) AS data_limite_envio,
  CAST(price AS DECIMAL(18, 2)) AS preco,
  CAST(freight_value AS DECIMAL(18, 2)) AS frete,
  CAST(price AS DECIMAL(18, 2)) + CAST(freight_value AS DECIMAL(18, 2)) AS valor_item,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_olist.bronze.order_items) AS _linhas_origem
FROM lakehouse_olist.bronze.order_items;

COMMENT ON COLUMN lakehouse_olist.silver.itens_pedido.valor_item IS
  'preco + frete deste item específico. Some por order_id para chegar ao valor total do pedido.';

ALTER TABLE lakehouse_olist.silver.itens_pedido
  ADD CONSTRAINT preco_nao_negativo CHECK (preco >= 0);

CREATE OR REPLACE TABLE lakehouse_olist.silver.pagamentos
COMMENT 'Silver — pagamentos tipados; um pedido pode ter várias linhas (parcelas/formas combinadas).'
AS
SELECT
  order_id,
  try_cast(payment_sequential AS INT) AS sequencial,
  payment_type AS tipo_pagamento,
  try_cast(payment_installments AS INT) AS parcelas,
  CAST(payment_value AS DECIMAL(18, 2)) AS valor_pagamento,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_olist.bronze.order_payments) AS _linhas_origem
FROM lakehouse_olist.bronze.order_payments;

CREATE OR REPLACE TABLE lakehouse_olist.silver.avaliacoes
COMMENT 'Silver — avaliações de pedido tipadas e deduplicadas por review_id (mantém a resposta mais recente).'
AS
WITH normalizado AS (
  SELECT
    review_id,
    order_id,
    try_cast(review_score AS INT) AS nota,
    review_comment_title AS titulo_comentario,
    review_comment_message AS mensagem_comentario,
    try_to_timestamp(review_creation_date) AS data_criacao,
    try_to_timestamp(review_answer_timestamp) AS data_resposta
  FROM lakehouse_olist.bronze.order_reviews
),
ranqueado AS (
  SELECT *,
    row_number() OVER (PARTITION BY review_id ORDER BY data_resposta DESC NULLS LAST) AS ordem
  FROM normalizado
)
SELECT
  review_id,
  order_id,
  nota,
  titulo_comentario,
  mensagem_comentario,
  data_criacao,
  data_resposta,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_olist.bronze.order_reviews) AS _linhas_origem
FROM ranqueado
WHERE ordem = 1;

ALTER TABLE lakehouse_olist.silver.avaliacoes
  ADD CONSTRAINT nota_entre_1_e_5 CHECK (nota BETWEEN 1 AND 5);
