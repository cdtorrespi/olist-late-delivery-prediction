-- =====================================================================
-- 03_star_schema.sql
-- Construye el modelo dimensional en el esquema "analytics":
--   dim_customer, dim_seller, dim_product, dim_date, dim_geo_zip
--   fact_order_items (grano: artículo de un pedido)
--   fact_orders      (grano: pedido)  <- tabla central del análisis
--
-- Decisiones clave (ver "Decisiones de diseño" en el README):
--   * La fecha estimada de entrega no tiene hora (siempre 00:00), así que
--     un pedido es "tarde" cuando el DÍA de entrega es posterior al día
--     estimado. Entregar el mismo día estimado cuenta como a tiempo.
--   * Los pedidos con estado "shipped" que nunca registraron entrega ya
--     habían pasado su fecha estimada al corte de los datos: se marcan como
--     'not_delivered' y cuentan como "no entregados a tiempo".
--   * Los prefijos postales de clientes y vendedores perdieron sus ceros a
--     la izquierda en los CSV (p. ej. "1151" en lugar de "01151"); se
--     normalizan a 5 dígitos con LPAD para poder cruzarlos con geolocalización.
--   * Ventana de análisis: compras de 2017-01-01 a 2018-08-31. Los meses
--     anteriores y posteriores tienen muy pocos pedidos.
-- =====================================================================

\set ON_ERROR_STOP on

DROP SCHEMA IF EXISTS analytics CASCADE;
CREATE SCHEMA analytics;

-- ---------------------------------------------------------------------
-- Geolocalización: un punto (promedio) por prefijo de código postal.
-- Se descartan coordenadas fuera de los límites de Brasil.
-- ---------------------------------------------------------------------
CREATE TABLE analytics.dim_geo_zip AS
SELECT
    geolocation_zip_code_prefix AS zip_prefix,
    AVG(geolocation_lat)        AS lat,
    AVG(geolocation_lng)        AS lng,
    COUNT(*)                    AS n_points
FROM raw.geolocation
WHERE geolocation_lat BETWEEN -33.8 AND 5.3
  AND geolocation_lng BETWEEN -73.99 AND -34.79
GROUP BY geolocation_zip_code_prefix;

ALTER TABLE analytics.dim_geo_zip ADD PRIMARY KEY (zip_prefix);

-- Distancia en km entre dos coordenadas (fórmula de Haversine)
CREATE OR REPLACE FUNCTION analytics.haversine_km(
    lat1 DOUBLE PRECISION, lng1 DOUBLE PRECISION,
    lat2 DOUBLE PRECISION, lng2 DOUBLE PRECISION)
RETURNS DOUBLE PRECISION
LANGUAGE sql IMMUTABLE AS $$
    SELECT 2 * 6371 * ASIN(SQRT(
        POWER(SIN(RADIANS(lat2 - lat1) / 2), 2) +
        COS(RADIANS(lat1)) * COS(RADIANS(lat2)) *
        POWER(SIN(RADIANS(lng2 - lng1) / 2), 2)))
$$;

-- ---------------------------------------------------------------------
-- Dimensiones
-- ---------------------------------------------------------------------
CREATE TABLE analytics.dim_customer AS
SELECT
    c.customer_id,
    c.customer_unique_id,
    LPAD(c.customer_zip_code_prefix, 5, '0') AS zip_prefix,
    INITCAP(c.customer_city)   AS city,
    c.customer_state           AS state,
    g.lat,
    g.lng
FROM raw.customers c
LEFT JOIN analytics.dim_geo_zip g ON g.zip_prefix = LPAD(c.customer_zip_code_prefix, 5, '0');

ALTER TABLE analytics.dim_customer ADD PRIMARY KEY (customer_id);

CREATE TABLE analytics.dim_seller AS
SELECT
    s.seller_id,
    LPAD(s.seller_zip_code_prefix, 5, '0') AS zip_prefix,
    INITCAP(s.seller_city)   AS city,
    s.seller_state           AS state,
    g.lat,
    g.lng
FROM raw.sellers s
LEFT JOIN analytics.dim_geo_zip g ON g.zip_prefix = LPAD(s.seller_zip_code_prefix, 5, '0');

ALTER TABLE analytics.dim_seller ADD PRIMARY KEY (seller_id);

CREATE TABLE analytics.dim_product AS
SELECT
    p.product_id,
    COALESCE(t.product_category_name_english, p.product_category_name, 'unknown') AS category,
    p.product_photos_qty                                    AS photos_qty,
    p.product_weight_g                                      AS weight_g,
    p.product_length_cm * p.product_height_cm * p.product_width_cm AS volume_cm3
FROM raw.products p
LEFT JOIN raw.category_translation t USING (product_category_name);

ALTER TABLE analytics.dim_product ADD PRIMARY KEY (product_id);

-- Calendario continuo que cubre todo el rango de los datos
CREATE TABLE analytics.dim_date AS
SELECT
    d::DATE                          AS date,
    EXTRACT(YEAR FROM d)::INT        AS year,
    EXTRACT(QUARTER FROM d)::INT     AS quarter,
    EXTRACT(MONTH FROM d)::INT       AS month,
    TO_CHAR(d, 'YYYY-MM')            AS year_month,
    EXTRACT(ISODOW FROM d)::INT      AS iso_weekday,   -- 1 = lunes
    (EXTRACT(ISODOW FROM d) >= 6)    AS is_weekend
FROM GENERATE_SERIES(DATE '2016-09-01', DATE '2018-12-31', INTERVAL '1 day') AS d;

ALTER TABLE analytics.dim_date ADD PRIMARY KEY (date);

-- ---------------------------------------------------------------------
-- Hechos a nivel artículo
-- ---------------------------------------------------------------------
CREATE TABLE analytics.fact_order_items AS
SELECT
    i.order_id,
    i.order_item_id,
    i.product_id,
    i.seller_id,
    i.price,
    i.freight_value,
    ROUND(analytics.haversine_km(s.lat, s.lng, c.lat, c.lng)::NUMERIC, 1) AS distance_km
FROM raw.order_items i
JOIN raw.orders o              ON o.order_id = i.order_id
JOIN analytics.dim_customer c  ON c.customer_id = o.customer_id
JOIN analytics.dim_seller s    ON s.seller_id = i.seller_id;

ALTER TABLE analytics.fact_order_items ADD PRIMARY KEY (order_id, order_item_id);

-- ---------------------------------------------------------------------
-- Hechos a nivel pedido
-- ---------------------------------------------------------------------
CREATE TABLE analytics.fact_orders AS
WITH
items AS (
    SELECT
        order_id,
        COUNT(*)                   AS n_items,
        COUNT(DISTINCT seller_id)  AS n_sellers,
        SUM(price)                 AS items_value,
        SUM(freight_value)         AS freight_value,
        MAX(distance_km)           AS max_distance_km
    FROM analytics.fact_order_items
    GROUP BY order_id
),
-- Vendedor principal: el del artículo de mayor precio (desempate: menor order_item_id)
main_seller AS (
    SELECT order_id, seller_id, product_id
    FROM (
        SELECT order_id, seller_id, product_id,
               ROW_NUMBER() OVER (PARTITION BY order_id ORDER BY price DESC, order_item_id) AS rn
        FROM raw.order_items
    ) x
    WHERE rn = 1
),
payments AS (
    SELECT
        order_id,
        SUM(payment_value)                                   AS payment_value,
        MAX(payment_installments)                            AS max_installments,
        -- Medio de pago principal: el de mayor monto
        (ARRAY_AGG(payment_type ORDER BY payment_value DESC))[1] AS main_payment_type
    FROM raw.order_payments
    GROUP BY order_id
),
-- Algunos pedidos tienen más de una reseña: se toma la más reciente
reviews AS (
    SELECT order_id, review_score
    FROM (
        SELECT order_id, review_score,
               ROW_NUMBER() OVER (PARTITION BY order_id
                                  ORDER BY review_answer_timestamp DESC, review_creation_date DESC) AS rn
        FROM raw.order_reviews
    ) x
    WHERE rn = 1
),
cutoff AS (
    SELECT MAX(order_purchase_timestamp) AS data_cutoff FROM raw.orders
)
SELECT
    o.order_id,
    o.customer_id,
    ms.seller_id                                   AS main_seller_id,
    ms.product_id                                  AS main_product_id,
    o.order_status,
    o.order_purchase_timestamp                     AS purchase_ts,
    o.order_purchase_timestamp::DATE               AS purchase_date,
    o.order_delivered_customer_date                AS delivered_ts,
    o.order_estimated_delivery_date::DATE          AS estimated_date,
    -- Plazo prometido al cliente (días naturales desde la compra)
    (o.order_estimated_delivery_date::DATE - o.order_purchase_timestamp::DATE) AS promised_days,
    -- Plazo real
    (o.order_delivered_customer_date::DATE - o.order_purchase_timestamp::DATE) AS actual_days,
    -- Días de retraso (negativo = llegó antes de lo prometido)
    (o.order_delivered_customer_date::DATE - o.order_estimated_delivery_date::DATE) AS days_vs_estimate,
    CASE
        WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL
             AND o.order_delivered_customer_date::DATE >  o.order_estimated_delivery_date::DATE THEN 'late'
        WHEN o.order_status = 'delivered' AND o.order_delivered_customer_date IS NOT NULL      THEN 'on_time'
        WHEN o.order_status = 'shipped'   AND o.order_estimated_delivery_date < cu.data_cutoff THEN 'not_delivered'
        WHEN o.order_status IN ('canceled', 'unavailable')                                     THEN 'canceled'
        ELSE 'other'
    END                                            AS delivery_status,
    i.n_items,
    i.n_sellers,
    i.items_value,
    i.freight_value,
    i.items_value + i.freight_value                AS gmv,
    i.max_distance_km,
    p.payment_value,
    p.main_payment_type,
    p.max_installments,
    r.review_score,
    (o.order_purchase_timestamp >= TIMESTAMP '2017-01-01'
     AND o.order_purchase_timestamp <  TIMESTAMP '2018-09-01') AS in_analysis_window
FROM raw.orders o
CROSS JOIN cutoff cu
LEFT JOIN items i       ON i.order_id = o.order_id
LEFT JOIN main_seller ms ON ms.order_id = o.order_id
LEFT JOIN payments p    ON p.order_id = o.order_id
LEFT JOIN reviews r     ON r.order_id = o.order_id;

ALTER TABLE analytics.fact_orders ADD PRIMARY KEY (order_id);
CREATE INDEX ON analytics.fact_orders (purchase_date);
CREATE INDEX ON analytics.fact_orders (main_seller_id);
CREATE INDEX ON analytics.fact_orders (customer_id);

-- Bandera de "no entregado a tiempo": objetivo del modelo
ALTER TABLE analytics.fact_orders ADD COLUMN is_late SMALLINT;
UPDATE analytics.fact_orders
SET is_late = CASE WHEN delivery_status IN ('late', 'not_delivered') THEN 1
                   WHEN delivery_status = 'on_time'                  THEN 0 END;

-- ---------------------------------------------------------------------
-- Controles de integridad
-- ---------------------------------------------------------------------
SELECT 'pedidos'                    AS control, COUNT(*)::TEXT AS valor FROM analytics.fact_orders
UNION ALL SELECT 'pedidos sin artículos',      COUNT(*)::TEXT FROM analytics.fact_orders WHERE n_items IS NULL
UNION ALL SELECT 'clientes sin coordenadas',   COUNT(*)::TEXT FROM analytics.dim_customer WHERE lat IS NULL
UNION ALL SELECT 'vendedores sin coordenadas', COUNT(*)::TEXT FROM analytics.dim_seller WHERE lat IS NULL
UNION ALL SELECT 'artículos huérfanos (sin pedido)',
          COUNT(*)::TEXT FROM raw.order_items i WHERE NOT EXISTS (SELECT 1 FROM raw.orders o WHERE o.order_id = i.order_id)
UNION ALL SELECT 'diferencia pagos vs GMV > 1 BRL (pedidos)',
          COUNT(*)::TEXT FROM analytics.fact_orders WHERE ABS(payment_value - gmv) > 1;

SELECT delivery_status, COUNT(*) AS pedidos
FROM analytics.fact_orders
WHERE in_analysis_window
GROUP BY delivery_status
ORDER BY pedidos DESC;
