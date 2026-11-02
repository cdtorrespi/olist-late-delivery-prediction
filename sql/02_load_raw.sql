-- =====================================================================
-- 02_load_raw.sql
-- Carga los 9 CSV al esquema "raw".
-- Uso (desde la raíz del repositorio):
--   psql -d olist -v data_dir="$PWD/data/raw" -f sql/02_load_raw.sql
-- =====================================================================

\set ON_ERROR_STOP on

\set f :data_dir '/olist_customers_dataset.csv'
COPY raw.customers FROM :'f' WITH (FORMAT csv, HEADER true);

\set f :data_dir '/olist_geolocation_dataset.csv'
COPY raw.geolocation FROM :'f' WITH (FORMAT csv, HEADER true);

\set f :data_dir '/olist_orders_dataset.csv'
COPY raw.orders FROM :'f' WITH (FORMAT csv, HEADER true);

\set f :data_dir '/olist_order_items_dataset.csv'
COPY raw.order_items FROM :'f' WITH (FORMAT csv, HEADER true);

\set f :data_dir '/olist_order_payments_dataset.csv'
COPY raw.order_payments FROM :'f' WITH (FORMAT csv, HEADER true);

\set f :data_dir '/olist_order_reviews_dataset.csv'
COPY raw.order_reviews FROM :'f' WITH (FORMAT csv, HEADER true);

\set f :data_dir '/olist_products_dataset.csv'
COPY raw.products FROM :'f' WITH (FORMAT csv, HEADER true);

\set f :data_dir '/olist_sellers_dataset.csv'
COPY raw.sellers FROM :'f' WITH (FORMAT csv, HEADER true);

\set f :data_dir '/product_category_name_translation.csv'
COPY raw.category_translation FROM :'f' WITH (FORMAT csv, HEADER true);

-- Verificación rápida de conteos
SELECT 'customers' AS tabla, COUNT(*) AS filas FROM raw.customers
UNION ALL SELECT 'geolocation', COUNT(*) FROM raw.geolocation
UNION ALL SELECT 'orders', COUNT(*) FROM raw.orders
UNION ALL SELECT 'order_items', COUNT(*) FROM raw.order_items
UNION ALL SELECT 'order_payments', COUNT(*) FROM raw.order_payments
UNION ALL SELECT 'order_reviews', COUNT(*) FROM raw.order_reviews
UNION ALL SELECT 'products', COUNT(*) FROM raw.products
UNION ALL SELECT 'sellers', COUNT(*) FROM raw.sellers
UNION ALL SELECT 'category_translation', COUNT(*) FROM raw.category_translation;
