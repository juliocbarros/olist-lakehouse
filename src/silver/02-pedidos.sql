-- Silver: pedidos tipados, com cancelamento, entrega e atraso explícitos.

CREATE OR REPLACE TABLE lakehouse_olist.silver.pedidos
COMMENT 'Silver — pedidos tipados; um pedido por linha, com datas do ciclo completo e flags derivadas.'
AS
SELECT
  order_id,
  customer_id,
  order_status AS status,
  order_status = 'canceled' AS cancelado,
  order_status = 'delivered' AS entregue,
  try_to_timestamp(order_purchase_timestamp) AS data_compra,
  try_to_timestamp(order_approved_at) AS data_aprovacao,
  try_to_timestamp(order_delivered_carrier_date) AS data_envio_transportadora,
  try_to_timestamp(order_delivered_customer_date) AS data_entrega_cliente,
  try_to_timestamp(order_estimated_delivery_date) AS data_estimada_entrega,
  datediff(
    try_to_timestamp(order_delivered_customer_date),
    try_to_timestamp(order_purchase_timestamp)
  ) AS tempo_entrega_dias,
  datediff(
    try_to_timestamp(order_delivered_customer_date),
    try_to_timestamp(order_estimated_delivery_date)
  ) AS atraso_dias,
  year(try_to_timestamp(order_purchase_timestamp)) AS ano,
  month(try_to_timestamp(order_purchase_timestamp)) AS mes,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_olist.bronze.orders) AS _linhas_origem
FROM lakehouse_olist.bronze.orders;

COMMENT ON COLUMN lakehouse_olist.silver.pedidos.tempo_entrega_dias IS
  'Dias entre compra e entrega ao cliente. Nulo se o pedido ainda não foi entregue.';
COMMENT ON COLUMN lakehouse_olist.silver.pedidos.atraso_dias IS
  'Positivo = entregue depois do prazo estimado; negativo ou zero = no prazo/antes. Nulo se não entregue.';

ALTER TABLE lakehouse_olist.silver.pedidos
  ADD CONSTRAINT data_compra_nao_nula CHECK (data_compra IS NOT NULL);

-- SEM CHECK "entregue implica data_entrega_cliente": pegadinha real do
-- dataset público Olist — 8 pedidos vêm com order_status = 'delivered' e
-- order_delivered_customer_date vazio na origem. É inconsistência do
-- sistema de origem, não erro de ingestão; tempo_entrega_dias/atraso_dias
-- ficam nulos para esses pedidos, o que já é o comportamento correto.
