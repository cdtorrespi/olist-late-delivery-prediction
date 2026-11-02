# Validación de medidas DAX contra SQL

Cada medida del modelo de Power BI se ejecutó con una consulta DAX y se comparó con la misma cifra calculada en PostgreSQL sobre `analytics.fact_orders`, filtrada a `in_analysis_window`. Las medidas de riesgo se compararon con `data/processed/test_predictions.csv`.

**Resultado:** las 26 medidas coinciden.

| Medida | DAX (Power BI) | Referencia (SQL / Python) | ¿Coincide? |
|---|---:|---:|:---:|
| Pedidos | 99,092 | 99,092 | Sí |
| Ingresos (GMV) | R$ 15,688,396.64 | R$ 15,688,396.64 | Sí |
| Ticket promedio | R$ 160.24 | R$ 160.24 | Sí |
| Ingresos (GMV), mar 2018 | R$ 1,152,785.45 | R$ 1,152,785.45 | Sí |
| Ingresos mes anterior, mar 2018 | R$ 980,154.60 | R$ 980,154.60 | Sí |
| Crecimiento mensual %, mar 2018 | 17.6% | 17.6% | Sí |
| Pedidos con resultado | 97,300 | 97,300 | Sí |
| Pedidos no a tiempo | 7,628 | 7,628 | Sí |
| % a tiempo | 92.16% | 92.16% | Sí |
| % no a tiempo | 7.84% | 7.84% | Sí |
| % a tiempo, clientes de RJ | 85.85% | 85.85% | Sí |
| Días prometidos (prom.) | 24.30 | 24.30 | Sí |
| Días reales (prom.) | 12.48 | 12.48 | Sí |
| Días de retraso (prom. tardíos) | 10.62 | 10.62 | Sí |
| Colchón promedio (días) | 11.82 | 24.30 − 12.48 | Sí |
| Calificación promedio | 4.089 | 4.089 | Sí |
| Reseñas | 98,330 | 98,330 | Sí |
| Reseñas negativas | 14,382 | 14,382 | Sí |
| % reseñas negativas | 14.63% | 14.63% | Sí |
| Reseñas negativas por retraso | 4,008 | 4,008 (`q4_negative_reviews_attribution.csv`) | Sí, después de la corrección |
| Pedidos evaluados | 32,453 | 32,453 | Sí |
| Pedidos marcados | 4,219 | 4,219 | Sí |
| % pedidos marcados | 13.0% | 13.0% | Sí |
| % retrasos capturados | 32.9% | 32.9% | Sí |
| Precisión de la alerta | 13.5% | 13.5% | Sí |
| Tasa de retraso (prueba) | 5.3% | 5.3% | Sí |
| Probabilidad promedio | 8.7% | 8.7% | Sí |
| Colchón promedio (ratio) | 1.87x | 1.87x | Sí |

## Error encontrado y corregido

La primera versión de **Reseñas negativas por retraso** daba 3,903 en lugar de 4,008. La medida filtraba los pedidos a tiempo con `fact_orders[is_late] = 0`, pero en DAX **un valor en blanco es igual a 0**. Por eso el filtro también incluía los 1,746 pedidos cancelados o en proceso, que tienen 83% de reseñas negativas, e inflaba la tasa de referencia de 9.2% a 10.7%.

Se corrigió filtrando por `fact_orders[delivery_status] = "on_time"`.
