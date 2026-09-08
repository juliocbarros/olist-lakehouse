-- Silver: produtos (com categoria traduzida) e vendedores tipados.

CREATE OR REPLACE TABLE lakehouse_olist.silver.produtos
COMMENT 'Silver — produtos tipados, com categoria em português e em inglês.'
AS
SELECT
  p.product_id,
  p.product_category_name AS categoria,
  coalesce(t.product_category_name_english, p.product_category_name) AS categoria_en,
  try_cast(p.product_weight_g AS INT) AS peso_g,
  try_cast(p.product_length_cm AS INT) AS comprimento_cm,
  try_cast(p.product_height_cm AS INT) AS altura_cm,
  try_cast(p.product_width_cm AS INT) AS largura_cm,
  try_cast(p.product_photos_qty AS INT) AS qtd_fotos,
  try_cast(p.product_name_lenght AS INT) AS tamanho_nome_caracteres,
  try_cast(p.product_description_lenght AS INT) AS tamanho_descricao_caracteres,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_olist.bronze.products) AS _linhas_origem
FROM lakehouse_olist.bronze.products p
LEFT JOIN lakehouse_olist.bronze.product_category_translation t
  ON t.product_category_name = p.product_category_name;

COMMENT ON COLUMN lakehouse_olist.silver.produtos.categoria_en IS
  'Tradução da categoria via product_category_translation; cai de volta para o nome em português quando não há tradução cadastrada.';

CREATE OR REPLACE TABLE lakehouse_olist.silver.vendedores
COMMENT 'Silver — vendedores (sellers) tipados.'
AS
SELECT
  seller_id,
  lpad(regexp_replace(trim(seller_zip_code_prefix), '[^0-9]', ''), 5, '0') AS cep_prefixo,
  initcap(trim(seller_city)) AS cidade,
  upper(trim(seller_state)) AS uf,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_olist.bronze.sellers) AS _linhas_origem
FROM lakehouse_olist.bronze.sellers;

ALTER TABLE lakehouse_olist.silver.vendedores
  ADD CONSTRAINT cep_prefixo_5_digitos CHECK (length(cep_prefixo) = 5);
