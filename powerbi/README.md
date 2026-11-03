# Power BI dashboard

The report has three pages, Executive, Logistics and Risk, and it is fed by the tables the project's scripts generate.

## Data

From the repository root:

```bash
psql -d olist -v out_dir="$PWD/data/processed" -f sql/05_export_model_base.sql
# run notebooks/02_features.ipynb and notebooks/03_model.ipynb
python src/export_powerbi.py
```

The script writes these tables to `data/processed/powerbi/`:

| Table | Grain | Rows |
|---|---|---:|
| `fact_orders` | order (purchases from January 2017 to August 2018) | 99,092 |
| `risk_orders` | test-period order (April to August 2018) with its risk | 32,453 |
| `dim_customer` | customer | 99,092 |
| `dim_seller` | seller | 3,095 |
| `dim_product` | product | 32,951 |
| `dim_date` | day (calculated table in DAX) | 608 |

In Power BI, the CSV folder is set in the Power Query parameter `DataFolder`, which you change under Transform data → Manage parameters. The path must end in `\`. Each table is loaded with `Csv.Document` and explicit data types.

## Data model

It is a constellation schema: two fact tables, `fact_orders` (all orders) and `risk_orders` (test-period orders with their risk), share the date, customer and seller dimensions. Because of that, a single date or state filter acts on both.

All relationships are one-to-many, from the dimension to the fact table, and filter in a single direction so there are no ambiguous paths between the two fact tables.

```
dim_date[Date]              1 ──< fact_orders[purchase_date]
dim_customer[customer_id]   1 ──< fact_orders[customer_id]
dim_seller[seller_id]       1 ──< fact_orders[seller_id]
dim_product[product_id]     1 ──< fact_orders[product_id]

dim_date[Date]              1 ──< risk_orders[purchase_date]
dim_customer[customer_id]   1 ──< risk_orders[customer_id]
dim_seller[seller_id]       1 ──< risk_orders[seller_id]
```

`dim_date` is a calculated table, marked as a date table so the time intelligence functions work:

```dax
dim_date =
ADDCOLUMNS (
    CALENDAR ( DATE ( 2017, 1, 1 ), DATE ( 2018, 8, 31 ) ),
    "year", YEAR ( [Date] ),
    "month", MONTH ( [Date] ),
    "month_name", FORMAT ( [Date], "mmm" ),
    "year_month", FORMAT ( [Date], "yyyy-mm" ),
    "weekday", WEEKDAY ( [Date], 2 )
)
```

Keys and columns not used in visuals are hidden. The 26 measures are in [`measures.dax`](measures.dax), grouped into four folders: Revenue, Logistics, Rating and Risk.

## Validation

I compared every measure with the same figure computed in PostgreSQL, and they all match. [`validation.md`](validation.md) has the full table, along with a DAX bug I found along the way and how I fixed it.

## Pages

All three pages are 1280 × 720 px and share the same layout: title, subtitle and a purchase date filter in the top right corner. The palette is restrained: blue `#2A78D6` for the main series, orange `#EB6834` for delays and alerts, and aqua `#1BAF7A` as a second comparison series.

Executive. At the top, four cards: revenue (GMV), orders, % on time and average rating. Below, two charts on the same month axis: revenue by month and the % of orders not on time. I put these two series in separate charts rather than one dual-axis chart, because with two scales on the same chart the visual relationship between them depends on how the axes happen to be set. On the right, the average rating by delivery outcome and a card with the impact of delays: extra negative reviews, % negative reviews, average days late and average order value.

Logistics. The % of orders not on time by customer state, sorted from highest to lowest. I used bars instead of a map because they compare the 27 states more precisely and do not depend on Power BI's map service. On the right, promised versus actual delivery time over time and a table of the sellers with the most late orders.

Risk. Four cards with the alert's results on the test period: orders flagged, % of late orders caught, precision and base rate. Two filters, by customer state and by seller state, and a table with every order ranked from the shortest buffer to the widest, with its late probability and the actual outcome.

The alert flags an order when its buffer (promised days ÷ days its route took over the last 90 days) falls below the 10th percentile of the previous 30 days. The probability in the table comes from the logistic regression and is there for reference.

## Report definition

The [`report/`](report/) folder contains the three pages in PBIR format: one `page.json` per page and one `visual.json` per visual, with its position, fields and formatting. To use them in another file:

1. Save the file as a Power BI project (File → Save as → *Power BI project files (.pbip)*) and close Power BI.
2. Copy `report/pages/` over `<project>.Report/definition/pages/`.
3. Reopen the `.pbip`.

The measure names in `report/` match [`measures.dax`](measures.dax), so the semantic model needs measures with those names.
