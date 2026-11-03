# Datos

Los datos crudos son el Brazilian E-Commerce Public Dataset by Olist (unos 100 mil pedidos hechos entre 2016 y 2018). No se guardan en este repositorio.

## Descarga

Opción A, Kaggle: descargar el dataset de <https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce> y descomprimir los 9 CSV en `data/raw/`.

Opción B, GitHub (no requiere cuenta), desde la raíz del repositorio:

```bash
git clone --depth 1 https://github.com/olist/work-at-olist-data.git /tmp/olist
cp /tmp/olist/datasets/*.csv data/raw/
```

Las dos fuentes tienen los mismos 9 archivos:

| Archivo | Filas |
|---|---:|
| olist_orders_dataset.csv | 99,441 |
| olist_order_items_dataset.csv | 112,650 |
| olist_order_payments_dataset.csv | 103,886 |
| olist_order_reviews_dataset.csv | 99,224 |
| olist_customers_dataset.csv | 99,441 |
| olist_sellers_dataset.csv | 3,095 |
| olist_products_dataset.csv | 32,951 |
| olist_geolocation_dataset.csv | 1,000,163 |
| product_category_name_translation.csv | 71 |

## Datos generados

`data/processed/` se llena al correr los notebooks (variables del modelo, predicciones del periodo de prueba y las tablas que importa Power BI). Git lo ignora porque todos sus archivos se pueden reconstruir a partir de los datos crudos.
