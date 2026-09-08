-- Gold: cinco dimensões conformadas. Lê SÓ da silver, nunca da bronze.

CREATE OR REPLACE TABLE lakehouse_olist.gold.dim_cliente
COMMENT 'Uma linha por PESSOA (customer_unique_id), com histórico de compra agregado através de todos os seus customer_id.'
AS
-- customer_id é por pedido; customer_unique_id é quem identifica a pessoa
-- (ver comentário em silver.clientes). Resolve para customer_unique_id
-- antes de agregar, senão cada compra do mesmo cliente vira "cliente novo".
WITH pedidos_cliente AS (
  SELECT
    c.customer_unique_id AS cliente_id,
    c.cidade,
    c.uf,
    c.cep_prefixo,
    p.order_id,
    p.data_compra,
    p.cancelado
  FROM lakehouse_olist.silver.clientes c
  JOIN lakehouse_olist.silver.pedidos p ON p.customer_id = c.customer_id
),
receita_pedido AS (
  SELECT order_id, SUM(valor_item) AS valor_pedido
  FROM lakehouse_olist.silver.itens_pedido
  GROUP BY order_id
),
agregado AS (
  SELECT
    pc.cliente_id,
    COUNT(DISTINCT pc.order_id) AS total_pedidos,
    SUM(CASE WHEN NOT pc.cancelado THEN coalesce(rp.valor_pedido, 0) ELSE 0 END) AS receita_acumulada,
    MIN(CASE WHEN NOT pc.cancelado THEN pc.data_compra END) AS data_primeiro_pedido,
    MAX(CASE WHEN NOT pc.cancelado THEN pc.data_compra END) AS data_ultimo_pedido
  FROM pedidos_cliente pc
  LEFT JOIN receita_pedido rp ON rp.order_id = pc.order_id
  GROUP BY pc.cliente_id
),
perfil_recente AS (
  -- endereço do pedido mais recente do cliente, já que ele pode ter
  -- comprado de endereços diferentes ao longo do tempo
  SELECT cliente_id, cidade, uf, cep_prefixo
  FROM (
    SELECT pc.cliente_id, pc.cidade, pc.uf, pc.cep_prefixo,
      row_number() OVER (PARTITION BY pc.cliente_id ORDER BY pc.data_compra DESC) AS ordem
    FROM pedidos_cliente pc
  )
  WHERE ordem = 1
)
SELECT
  a.cliente_id AS customer_unique_id,
  pr.cidade,
  pr.uf,
  pr.cep_prefixo,
  a.data_primeiro_pedido,
  a.data_ultimo_pedido,
  a.total_pedidos,
  a.receita_acumulada,
  datediff(current_date(), a.data_ultimo_pedido) AS dias_sem_comprar
FROM agregado a
JOIN perfil_recente pr ON pr.cliente_id = a.cliente_id;

COMMENT ON COLUMN lakehouse_olist.gold.dim_cliente.total_pedidos IS
  'Conta pedidos distintos do cliente, cancelados inclusos — é contagem de interação comercial, não de receita.';
COMMENT ON COLUMN lakehouse_olist.gold.dim_cliente.data_ultimo_pedido IS
  'Data do último pedido NÃO cancelado — cancelamento não conta como compra.';
COMMENT ON COLUMN lakehouse_olist.gold.dim_cliente.cidade IS
  'Cidade/UF/CEP do pedido mais recente do cliente — pode mudar ao longo do tempo se ele mudar de endereço.';

CREATE OR REPLACE TABLE lakehouse_olist.gold.dim_produto
COMMENT 'Uma linha por product_id: categoria e dimensões físicas de catálogo.'
AS
SELECT
  product_id,
  categoria,
  categoria_en,
  peso_g,
  comprimento_cm,
  altura_cm,
  largura_cm,
  qtd_fotos
FROM lakehouse_olist.silver.produtos;

CREATE OR REPLACE TABLE lakehouse_olist.gold.dim_vendedor
COMMENT 'Uma linha por seller_id: localização do vendedor.'
AS
SELECT
  seller_id,
  cep_prefixo,
  cidade,
  uf
FROM lakehouse_olist.silver.vendedores;

CREATE OR REPLACE TABLE lakehouse_olist.gold.dim_geografia
COMMENT 'Uma linha por CEP-prefixo: coordenadas médias para mapas e agregações regionais.'
AS
SELECT
  cep_prefixo,
  cidade,
  uf,
  latitude,
  longitude
FROM lakehouse_olist.silver.geolocalizacao;

CREATE OR REPLACE TABLE lakehouse_olist.gold.dim_calendario
COMMENT 'Uma linha por dia, cobrindo o período real de pedidos (calculado dinamicamente, não fixo).'
AS
WITH intervalo AS (
  SELECT MIN(data_compra) AS inicio, MAX(data_compra) AS fim
  FROM lakehouse_olist.silver.pedidos
)
SELECT
  CAST(d AS DATE) AS data,
  year(d) AS ano,
  month(d) AS mes,
  date_format(d, 'MMMM') AS nome_mes,
  quarter(d) AS trimestre,
  date_format(d, 'EEEE') AS dia_semana,
  month(d) IN (5, 8, 11, 12) AS mes_pico_varejo_br
FROM intervalo
LATERAL VIEW explode(sequence(CAST(inicio AS DATE), CAST(fim AS DATE), interval 1 day)) AS d;

COMMENT ON COLUMN lakehouse_olist.gold.dim_calendario.mes_pico_varejo_br IS
  'Maio (Dia das Mães), agosto (Dia dos Pais), novembro (Black Friday) e dezembro (Natal) são os meses de pico do varejo brasileiro.';
