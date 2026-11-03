# DAX measure validation

I ran every measure in the model with a DAX query and compared the result with the same figure computed in PostgreSQL on `analytics.fact_orders`, filtered to `in_analysis_window`. The risk measures I compared with `data/processed/test_predictions.csv`. All 26 match.

| Measure | Power BI | Reference (SQL or Python) | Match? |
|---|---:|---:|:---:|
| Orders | 99,092 | 99,092 | Yes |
| Revenue (GMV) | R$ 15,688,396.64 | R$ 15,688,396.64 | Yes |
| Average order value | R$ 160.24 | R$ 160.24 | Yes |
| Revenue (GMV), March 2018 | R$ 1,152,785.45 | R$ 1,152,785.45 | Yes |
| Revenue previous month, March 2018 | R$ 980,154.60 | R$ 980,154.60 | Yes |
| Monthly growth %, March 2018 | 17.6% | 17.6% | Yes |
| Orders with outcome | 97,300 | 97,300 | Yes |
| Orders not on time | 7,628 | 7,628 | Yes |
| % on time | 92.16% | 92.16% | Yes |
| % not on time | 7.84% | 7.84% | Yes |
| % on time, RJ customers | 85.85% | 85.85% | Yes |
| Promised days (avg) | 24.30 | 24.30 | Yes |
| Actual days (avg) | 12.48 | 12.48 | Yes |
| Days late (avg, late orders) | 10.62 | 10.62 | Yes |
| Average buffer (days) | 11.82 | 24.30 − 12.48 | Yes |
| Average rating | 4.089 | 4.089 | Yes |
| Reviews | 98,330 | 98,330 | Yes |
| Negative reviews | 14,382 | 14,382 | Yes |
| % negative reviews | 14.63% | 14.63% | Yes |
| Negative reviews from delays | 4,008 | 4,008 | Yes, after the fix |
| Orders evaluated | 32,453 | 32,453 | Yes |
| Orders flagged | 4,219 | 4,219 | Yes |
| % orders flagged | 13.0% | 13.0% | Yes |
| % late orders caught | 32.9% | 32.9% | Yes |
| Alert precision | 13.5% | 13.5% | Yes |
| Late rate (test) | 5.3% | 5.3% | Yes |
| Average probability | 8.7% | 8.7% | Yes |
| Average buffer (ratio) | 1.87x | 1.87x | Yes |

## A bug I found

The first version of "Negative reviews from delays" returned 3,903 instead of 4,008. The measure picked on-time orders with the filter `fact_orders[is_late] = 0`, but in DAX a blank value is treated as equal to 0. So the filter also included the 1,746 canceled or in-progress orders, which have 83% negative reviews, and the reference rate rose from 9.2% to 10.7%.

I fixed it by filtering on `fact_orders[delivery_status] = "on_time"`.
