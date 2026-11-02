-- =====================================================================
-- 04_analysis.sql
-- Consultas de análisis sobre el modelo dimensional. Cada resultado se
-- exporta a reports/sql_results/ para el reporte y el dashboard.
-- Uso (desde la raíz del repositorio):
--   psql -d olist -v out_dir="$PWD/reports/sql_results" -f sql/04_analysis.sql
-- Universo: compras de 2017-01 a 2018-08 (in_analysis_window).
-- =====================================================================

\set ON_ERROR_STOP on
\pset footer off

-- Vista base: pedidos de la ventana de análisis con resultado de entrega conocido
CREATE OR REPLACE VIEW analytics.v_orders_outcome AS
SELECT *
FROM analytics.fact_orders
WHERE in_analysis_window
  AND delivery_status IN ('on_time', 'late', 'not_delivered');

-- ---------------------------------------------------------------------
-- Q1. KPIs mensuales: pedidos, GMV, crecimiento mes a mes (LAG),
--     GMV acumulado y % de entregas a tiempo.
-- ---------------------------------------------------------------------
\echo '== Q1. KPIs mensuales =='
\set f :out_dir '/q1_monthly_kpis.csv'
\set q 'WITH monthly AS ( SELECT DATE_TRUNC(''month'', purchase_date)::DATE AS month, COUNT(*) AS orders, ROUND(SUM(gmv), 2) AS gmv, ROUND(AVG(promised_days), 1) AS avg_promised_days, ROUND(AVG(actual_days), 1) AS avg_actual_days, ROUND(100.0 * AVG(1 - is_late), 2) AS on_time_pct, ROUND(AVG(review_score), 3) AS avg_review FROM analytics.v_orders_outcome GROUP BY 1 ) SELECT month, orders, gmv, ROUND(100.0 * (gmv / LAG(gmv) OVER (ORDER BY month) - 1), 1) AS gmv_mom_pct, SUM(gmv) OVER (ORDER BY month) AS gmv_running_total, avg_promised_days, avg_actual_days, on_time_pct, avg_review FROM monthly ORDER BY month'
:q;
\set c '\\copy (' :q ') TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c

-- ---------------------------------------------------------------------
-- Q2. Calificación según resultado de la entrega
-- ---------------------------------------------------------------------
\echo '== Q2. Calificación por resultado de entrega =='
\set f :out_dir '/q2_review_by_delivery_status.csv'
\set q 'SELECT delivery_status, COUNT(*) AS orders, COUNT(review_score) AS reviews, ROUND(AVG(review_score), 2) AS avg_review, ROUND(100.0 * AVG(CASE WHEN review_score <= 2 THEN 1.0 ELSE 0 END) FILTER (WHERE review_score IS NOT NULL), 1) AS negative_pct, ROUND(100.0 * AVG(CASE WHEN review_score = 5 THEN 1.0 ELSE 0 END) FILTER (WHERE review_score IS NOT NULL), 1) AS five_star_pct FROM analytics.v_orders_outcome GROUP BY delivery_status ORDER BY avg_review DESC'
:q;
\set c '\\copy (' :q ') TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c

-- ---------------------------------------------------------------------
-- Q3. Calificación según los días de retraso (curva dosis-respuesta)
-- ---------------------------------------------------------------------
\echo '== Q3. Calificación por días contra la fecha prometida =='
\set f :out_dir '/q3_review_by_days_late.csv'
\set q 'WITH b AS ( SELECT CASE WHEN days_vs_estimate <= -15 THEN ''01. 15+ días antes'' WHEN days_vs_estimate <= -8 THEN ''02. 8-14 días antes'' WHEN days_vs_estimate <= -1 THEN ''03. 1-7 días antes'' WHEN days_vs_estimate = 0 THEN ''04. el día prometido'' WHEN days_vs_estimate <= 3 THEN ''05. 1-3 días tarde'' WHEN days_vs_estimate <= 7 THEN ''06. 4-7 días tarde'' WHEN days_vs_estimate <= 14 THEN ''07. 8-14 días tarde'' ELSE ''08. 15+ días tarde'' END AS bucket, review_score FROM analytics.v_orders_outcome WHERE delivery_status IN (''on_time'', ''late'') ) SELECT bucket, COUNT(*) AS orders, ROUND(AVG(review_score), 2) AS avg_review, ROUND(100.0 * AVG(CASE WHEN review_score <= 2 THEN 1.0 ELSE 0 END) FILTER (WHERE review_score IS NOT NULL), 1) AS negative_pct FROM b GROUP BY bucket ORDER BY bucket'
:q;
\set c '\\copy (' :q ') TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c

-- ---------------------------------------------------------------------
-- Q4. ¿Cuántas reseñas negativas "sobran" por los retrasos?
--     Exceso = reseñas negativas de pedidos tardíos menos las que habría
--     si esos pedidos tuvieran la tasa negativa de los pedidos a tiempo.
-- ---------------------------------------------------------------------
\echo '== Q4. Reseñas negativas atribuibles a retrasos =='
\set f :out_dir '/q4_negative_reviews_attribution.csv'
\set q 'WITH r AS ( SELECT is_late, COUNT(*) AS reviews, SUM(CASE WHEN review_score <= 2 THEN 1 ELSE 0 END) AS negatives FROM analytics.v_orders_outcome WHERE review_score IS NOT NULL GROUP BY is_late ), w AS ( SELECT MAX(CASE WHEN is_late = 0 THEN negatives::NUMERIC / reviews END) AS neg_rate_on_time, MAX(CASE WHEN is_late = 1 THEN negatives::NUMERIC / reviews END) AS neg_rate_late, MAX(CASE WHEN is_late = 1 THEN reviews END) AS late_reviews, MAX(CASE WHEN is_late = 1 THEN negatives END) AS late_negatives, SUM(negatives) AS total_negatives, SUM(reviews) AS total_reviews FROM r ) SELECT total_reviews, total_negatives, late_reviews, late_negatives, ROUND(100 * neg_rate_on_time, 1) AS neg_rate_on_time_pct, ROUND(100 * neg_rate_late, 1) AS neg_rate_late_pct, ROUND(late_reviews * (neg_rate_late - neg_rate_on_time)) AS excess_negatives_from_delays, ROUND(100 * late_reviews * (neg_rate_late - neg_rate_on_time) / total_negatives, 1) AS excess_share_of_all_negatives_pct FROM w'
:q;
\set c '\\copy (' :q ') TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c

-- ---------------------------------------------------------------------
-- Q5. Desempeño por estado del cliente, con ranking (RANK)
-- ---------------------------------------------------------------------
\echo '== Q5. Estados del cliente =='
\set f :out_dir '/q5_by_customer_state.csv'
\set q 'WITH s AS ( SELECT c.state, COUNT(*) AS orders, ROUND(100.0 * AVG(o.is_late), 1) AS late_pct, ROUND(AVG(o.promised_days), 1) AS avg_promised_days, ROUND(AVG(o.actual_days), 1) AS avg_actual_days, ROUND(AVG(o.max_distance_km)) AS avg_distance_km, ROUND(AVG(o.review_score), 2) AS avg_review FROM analytics.v_orders_outcome o JOIN analytics.dim_customer c USING (customer_id) GROUP BY c.state HAVING COUNT(*) >= 100 ) SELECT RANK() OVER (ORDER BY late_pct DESC) AS late_rank, s.* FROM s ORDER BY late_rank'
:q;
\set c '\\copy (' :q ') TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c

-- ---------------------------------------------------------------------
-- Q6. Concentración de retrasos por vendedor (Pareto con ventanas)
-- ---------------------------------------------------------------------
\echo '== Q6. Concentración de retrasos por vendedor =='
\set f :out_dir '/q6_seller_pareto.csv'
\set q 'WITH s AS ( SELECT main_seller_id AS seller_id, COUNT(*) AS orders, SUM(is_late) AS late_orders FROM analytics.v_orders_outcome GROUP BY main_seller_id ), ranked AS ( SELECT seller_id, orders, late_orders, ROUND(100.0 * late_orders / orders, 1) AS late_pct, ROW_NUMBER() OVER (ORDER BY late_orders DESC, orders) AS seller_rank, COUNT(*) OVER () AS n_sellers, SUM(late_orders) OVER () AS total_late, SUM(late_orders) OVER (ORDER BY late_orders DESC, orders ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS cum_late FROM s ) SELECT seller_rank, seller_id, orders, late_orders, late_pct, ROUND(100.0 * seller_rank / n_sellers, 2) AS cum_sellers_pct, ROUND(100.0 * cum_late / total_late, 1) AS cum_late_share_pct FROM ranked ORDER BY seller_rank'
\set c '\\copy (' :q ') TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c
-- Resumen: ¿qué % de vendedores concentra el 50% y el 80% de los retrasos?
WITH s AS (
    SELECT main_seller_id, COUNT(*) AS orders, SUM(is_late) AS late_orders
    FROM analytics.v_orders_outcome GROUP BY main_seller_id
), r AS (
    SELECT late_orders,
           ROW_NUMBER() OVER (ORDER BY late_orders DESC, orders) AS rk,
           COUNT(*) OVER () AS n,
           SUM(late_orders) OVER (ORDER BY late_orders DESC, orders) * 1.0 / SUM(late_orders) OVER () AS cum_share
    FROM s
)
SELECT MAX(n) AS sellers,
       MIN(rk) FILTER (WHERE cum_share >= 0.5) AS sellers_for_50pct_of_late,
       ROUND(100.0 * MIN(rk) FILTER (WHERE cum_share >= 0.5) / MAX(n), 1) AS pct_sellers_50,
       MIN(rk) FILTER (WHERE cum_share >= 0.8) AS sellers_for_80pct_of_late,
       ROUND(100.0 * MIN(rk) FILTER (WHERE cum_share >= 0.8) / MAX(n), 1) AS pct_sellers_80
FROM r;

-- ---------------------------------------------------------------------
-- Q7. Retrasos por distancia vendedor-cliente
-- ---------------------------------------------------------------------
\echo '== Q7. Retrasos por distancia =='
\set f :out_dir '/q7_late_by_distance.csv'
\set q 'SELECT CASE WHEN max_distance_km < 100 THEN ''01. <100 km'' WHEN max_distance_km < 500 THEN ''02. 100-499 km'' WHEN max_distance_km < 1000 THEN ''03. 500-999 km'' WHEN max_distance_km < 2000 THEN ''04. 1,000-1,999 km'' ELSE ''05. 2,000+ km'' END AS distance_band, COUNT(*) AS orders, ROUND(100.0 * AVG(is_late), 1) AS late_pct, ROUND(AVG(promised_days), 1) AS avg_promised_days, ROUND(AVG(actual_days), 1) AS avg_actual_days FROM analytics.v_orders_outcome WHERE max_distance_km IS NOT NULL GROUP BY 1 ORDER BY 1'
:q;
\set c '\\copy (' :q ') TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c

-- ---------------------------------------------------------------------
-- Q8. Categorías con más retrasos (mínimo 500 pedidos)
-- ---------------------------------------------------------------------
\echo '== Q8. Categorías =='
\set f :out_dir '/q8_by_category.csv'
\set q 'SELECT p.category, COUNT(*) AS orders, ROUND(100.0 * AVG(o.is_late), 1) AS late_pct, ROUND(SUM(o.gmv), 0) AS gmv, ROUND(AVG(o.review_score), 2) AS avg_review FROM analytics.v_orders_outcome o JOIN analytics.dim_product p ON p.product_id = o.main_product_id GROUP BY p.category HAVING COUNT(*) >= 500 ORDER BY late_pct DESC'
:q;
\set c '\\copy (' :q ') TO ' :'f' ' WITH (FORMAT csv, HEADER true)'
:c
