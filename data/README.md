# Data

The raw data is the **Brazilian E-Commerce Public Dataset by Olist** (about 100k orders placed between 2016 and 2018). It is not stored in this repository.

## Download

Option A, Kaggle: download the dataset from <https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce> and unzip the 9 CSV files into `data/raw/`.

Option B, GitHub (no login required), from the repository root:

```bash
git clone --depth 1 https://github.com/olist/work-at-olist-data.git /tmp/olist
cp /tmp/olist/datasets/*.csv data/raw/
```

Both sources contain the same 9 files:

| File | Rows |
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

## Generated data

`data/processed/` is filled by the notebooks (model features, test-period predictions and the tables imported by Power BI). It is ignored by git because every file in it can be rebuilt from the raw data.
