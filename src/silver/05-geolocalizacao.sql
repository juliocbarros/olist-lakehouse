-- Silver: geolocalização agregada por CEP-prefixo.
-- A bronze tem várias linhas de lat/lng por cep_prefixo (múltiplos pontos
-- geocodificados dentro da mesma região). Para virar dimensão, agregamos
-- em um ponto médio por cep_prefixo — não é a coordenada exata de nenhum
-- endereço, é uma aproximação para mapas e agregações regionais.

CREATE OR REPLACE TABLE lakehouse_olist.silver.geolocalizacao
COMMENT 'Silver — um ponto médio (lat/lng) por CEP-prefixo, agregado a partir de múltiplas coordenadas da bronze.'
AS
SELECT
  lpad(regexp_replace(trim(geolocation_zip_code_prefix), '[^0-9]', ''), 5, '0') AS cep_prefixo,
  avg(try_cast(geolocation_lat AS DOUBLE)) AS latitude,
  avg(try_cast(geolocation_lng AS DOUBLE)) AS longitude,
  first(initcap(trim(geolocation_city)), true) AS cidade,
  first(upper(trim(geolocation_state)), true) AS uf,
  count(*) AS qtd_pontos_origem,
  current_timestamp() AS _processado_em,
  (SELECT COUNT(*) FROM lakehouse_olist.bronze.geolocation) AS _linhas_origem
FROM lakehouse_olist.bronze.geolocation
GROUP BY lpad(regexp_replace(trim(geolocation_zip_code_prefix), '[^0-9]', ''), 5, '0');

COMMENT ON COLUMN lakehouse_olist.silver.geolocalizacao.qtd_pontos_origem IS
  'Quantas linhas da bronze foram agregadas para formar este ponto médio — maior valor indica média mais estável.';

ALTER TABLE lakehouse_olist.silver.geolocalizacao
  ADD CONSTRAINT cep_prefixo_5_digitos CHECK (length(cep_prefixo) = 5);
