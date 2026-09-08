-- Silver: clientes tipados.
-- ANSI mode está ligado neste workspace: to_date sobre data malformada
-- ABORTA a query em vez de virar NULL. Por isso try_to_date sempre.
--
-- QUIRK DO DATASET OLIST: customer_id é gerado por pedido, não por pessoa.
-- O mesmo cliente real, ao comprar duas vezes, ganha dois customer_id
-- diferentes. customer_unique_id é quem identifica a pessoa de fato — é
-- ele que a gold.dim_cliente usa para agregar o histórico de compras.

CREATE OR REPLACE TABLE lakehouse_olist.silver.clientes
COMMENT 'Silver — clientes tipados. Uma linha por customer_id (grão de pedido, não de pessoa).'
AS
SELECT
  customer_id,
  customer_unique_id,
  lpad(regexp_replace(trim(customer_zip_code_prefix), '[^0-9]', ''), 5, '0') AS cep_prefixo,
  initcap(trim(customer_city)) AS cidade,
  upper(trim(customer_state)) AS uf,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_olist.bronze.customers) AS _linhas_origem
FROM lakehouse_olist.bronze.customers;

COMMENT ON COLUMN lakehouse_olist.silver.clientes.customer_unique_id IS
  'Identifica a pessoa real. Um mesmo customer_unique_id pode aparecer em várias linhas (uma por pedido) — não é chave única desta tabela.';
COMMENT ON COLUMN lakehouse_olist.silver.clientes.cep_prefixo IS
  'Normalizado para 5 dígitos com lpad de zero à esquerda. Nunca convertido para número.';

ALTER TABLE lakehouse_olist.silver.clientes
  ADD CONSTRAINT cep_prefixo_5_digitos CHECK (length(cep_prefixo) = 5);
ALTER TABLE lakehouse_olist.silver.clientes
  ADD CONSTRAINT uf_2_letras CHECK (length(uf) = 2);
