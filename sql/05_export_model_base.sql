-- =====================================================================
-- 05_export_model_base.sql
-- Exports from the dimensional model the tables used by the Python
-- notebooks and the Power BI dashboard.
-- Usage (from the repository root):
--   psql -d olist -v out_dir="$PWD/data/processed" -f sql/05_export_model_base.sql
-- =====================================================================

\set ON_ERROR_STOP on

-- Model base: one row per order with a known delivery outcome, holding
-- only information available AT PURCHASE TIME, plus the outcome columns
-- (is_late, delivered_ts, review_score) that are used as the target or
-- for evaluation, never as features.
CREATE OR REPLACE VIEW analytics.v_model_base AS
WITH item_agg AS (
    SELECT
        i.order_id,
        SUM(p.weight_g)                      AS total_weight_g,
        SUM(p.volume_cm3)                    AS total_volume_cm3,
        COUNT(DISTINCT p.category)           AS n_categories
    FROM analytics.fact_order_items i
    LEFT JOIN analytics.dim_product p USING (product_id)
    GROUP BY i.order_id
)
SELECT
    o.order_id,
    o.purchase_ts,
    o.estimated_date,
    o.delivered_ts,
    o.delivery_status,
    o.is_late,
    o.review_score,
    o.days_vs_estimate,
    o.main_seller_id,
    o.promised_days,
    o.n_items,
    o.n_sellers,
    o.items_value,
    o.freight_value,
    o.max_distance_km,
    o.main_payment_type,
    o.max_installments,
    c.state       AS customer_state,
    c.lat         AS customer_lat,
    c.lng         AS customer_lng,
    s.state       AS seller_state,
    p.category    AS main_category,
    p.photos_qty  AS main_photos_qty,
    a.total_weight_g,
    a.total_volume_cm3,
    a.n_categories
FROM analytics.fact_orders o
JOIN analytics.dim_customer c ON c.customer_id = o.customer_id
LEFT JOIN analytics.dim_seller s ON s.seller_id = o.main_seller_id
LEFT JOIN analytics.dim_product p ON p.product_id = o.main_product_id
LEFT JOIN item_agg a ON a.order_id = o.order_id
WHERE o.in_analysis_window
  AND o.delivery_status IN ('on_time', 'late', 'not_delivered');

\set f :out_dir '/model_base.csv'
\set c '\\copy (SELECT * FROM analytics.v_model_base ORDER BY purchase_ts) TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c

-- Dimensional model tables for Power BI
\set f :out_dir '/pbi_fact_orders.csv'
\set c '\\copy (SELECT order_id, customer_id, main_seller_id AS seller_id, main_product_id AS product_id, order_status, delivery_status, is_late, purchase_date, estimated_date, delivered_ts::DATE AS delivered_date, promised_days, actual_days, days_vs_estimate, n_items, items_value, freight_value, gmv, max_distance_km, main_payment_type, review_score FROM analytics.fact_orders WHERE in_analysis_window ORDER BY purchase_date) TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c

\set f :out_dir '/pbi_dim_customer.csv'
\set c '\\copy (SELECT customer_id, customer_unique_id, city, state, lat, lng FROM analytics.dim_customer) TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c

\set f :out_dir '/pbi_dim_seller.csv'
\set c '\\copy (SELECT seller_id, city, state, lat, lng FROM analytics.dim_seller) TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c

\set f :out_dir '/pbi_dim_product.csv'
\set c '\\copy (SELECT product_id, category, weight_g, volume_cm3 FROM analytics.dim_product) TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c
