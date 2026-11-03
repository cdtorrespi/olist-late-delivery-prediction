# Riesgo de entrega tardía en Olist: SQL, machine learning y Power BI

En un marketplace en línea, un pedido que llega tarde casi siempre termina en una mala reseña, y las malas reseñas pesan en las ventas futuras del vendedor y de la plataforma. El daño ocurre después de la compra, pero la oportunidad de evitarlo está antes: al momento de comprar todavía se puede prometer una fecha más realista o darle prioridad al envío.

Con 100 mil pedidos reales de Olist, un marketplace brasileño, quise responder si es posible saber desde la compra qué pedidos van a llegar tarde, y qué tanto vale la pena hacerlo. Usé PostgreSQL para el modelo de datos, Python para el análisis y el modelo, y Power BI para el dashboard.

## Lo que encontré

### Los retrasos explican buena parte de las malas reseñas

Lo primero fue confirmar que el problema importaba. Los pedidos tardíos promedian 2.3 estrellas contra 4.3 de los que llegan a tiempo, y el 62% de sus reseñas son negativas (1 o 2 estrellas), contra 9% en los pedidos puntuales. En total, los retrasos explican unas 4,000 reseñas negativas adicionales, el 31% de todas las del periodo.

### El riesgo está en la promesa, no solo en el envío

La señal más fuerte no estaba en el producto ni en el vendedor, sino en qué tan ajustada era la fecha prometida. En la importancia por permutación del modelo, esa variable pesa casi el triple que la siguiente. Lo medí como una razón: días prometidos entre lo que tardó la misma ruta (estado del vendedor a estado del cliente) en los últimos 90 días. Entre los pedidos con la razón más ajustada, el 19% llega tarde; entre los de mayor margen, menos del 4%.

### Una regla simple le ganó a los modelos

Esperaba que un modelo de machine learning con más información superara a esa razón, así que entrené una regresión logística y un gradient boosting con 26 variables. No fue así. Si se marca el 10% de pedidos con la razón más ajustada, se detecta el 29.4% de todos los retrasos (IC 95%: 27.4–31.3%), unas tres veces lo que detectaría una selección al azar. Los dos modelos detectaron unos 3.5 puntos porcentuales menos, y la diferencia es estadísticamente significativa. Lo evalué en abril–agosto de 2018, un periodo que ningún modelo vio durante el desarrollo.

El backtest mes por mes explicó por qué. Los tiempos de entrega de Olist cambiaron rápido en 2018 y los modelos envejecieron mal: el gradient boosting llegó a quedar por debajo del azar en agosto de 2018. La razón, en cambio, se recalcula con los últimos 90 días de cada ruta, se adapta sola y nunca bajó de 16.7%. Para este problema, la solución más simple también era la más estable.

## Qué recomendaría

1. Fijar un margen mínimo en la fecha prometida: nunca prometer menos de 1.3 veces el tiempo reciente de la ruta. En el periodo de prueba, esto habría movido la fecha del 22% de los pedidos, 3.6 días en promedio, y 398 pedidos tardíos (23%) habrían llegado a tiempo. Una promesa más larga puede costar ventas, y estos datos solo incluyen compras concretadas, así que lo lanzaría primero como prueba A/B.
2. Dar al equipo de logística una alerta diaria con los pedidos cuya razón quede por debajo del percentil 10 de los últimos 30 días. En el periodo de prueba, la alerta marcó el 13% de los pedidos y detectó el 33% de los retrasos; el 13.5% de los pedidos marcados llegó tarde, 2.5 veces la tasa base. El umbral se ajusta solo, así que no hay que reentrenar nada.

## Dashboard

![Página ejecutiva del dashboard de Power BI](assets/dashboard.png)

El reporte de Power BI tiene tres páginas: un resumen ejecutivo (ingresos, pedidos, tasa de entregas a tiempo y calificación), una vista de logística (retrasos por estado, días prometidos contra reales y vendedores con más retrasos) y una vista de riesgo que ordena los pedidos del periodo de prueba del margen más ajustado al más holgado.

| Logística | Riesgo |
|---|---|
| ![Página de logística](assets/dashboard_logistica.png) | ![Página de riesgo](assets/dashboard_riesgo.png) |

El modelo de datos, las medidas DAX y la definición del reporte están en [`powerbi/`](powerbi/).

## Cómo lo construí

| Etapa | Herramientas | Qué hace |
|---|---|---|
| Modelo de datos | PostgreSQL 16 | Carga las 9 tablas originales en un modelo dimensional con dos tablas de hechos a distinta granularidad (`fact_orders` por pedido y `fact_order_items` por artículo) y dimensiones compartidas de cliente, vendedor, producto y fecha. Las consultas de análisis usan CTE y funciones de ventana (`LAG`, `RANK`, acumulados y participación tipo Pareto). |
| Exploración | pandas, matplotlib | Balance de la variable objetivo, tendencias en el tiempo, efecto en las reseñas y calidad de datos. |
| Variables | pandas | Historial de vendedores y rutas usando solo información disponible al momento de la compra. |
| Modelo | scikit-learn | Regla de la razón contra regresión logística y gradient boosting, elegidos en un periodo de validación y evaluados fuera de tiempo, con intervalos bootstrap, backtest mensual e importancia por permutación. |
| Dashboard | Power BI, DAX | Dos tablas de hechos (todos los pedidos y los puntajes de riesgo del periodo de prueba) con las mismas dimensiones y relaciones uno a muchos en una sola dirección. 26 medidas, cada una verificada contra SQL. |

### Decisiones de diseño

- Qué cuenta como retraso: un pedido llega tarde si se entregó después del día prometido. También cuento los 1,097 pedidos enviados que nunca se entregaron, porque todos ya habían pasado su fecha prometida cuando terminan los datos; dejarlos fuera escondería los peores casos.
- Sin información del futuro: el historial de un vendedor o de una ruta solo incluye pedidos cuyo resultado ya se conocía al momento de la compra. Un pedido a tiempo cuenta desde que se entrega; uno tardío, desde que pasa su día prometido. Comparé la implementación eficiente con una versión de fuerza bruta en 500 pedidos al azar y coincidieron exactamente.
- Quité variables que envejecen mal: el mes de compra y los volúmenes absolutos de pedidos hacían que los modelos memorizaran el periodo de entrenamiento. La ventana de 90 días para el historial de rutas se eligió en el periodo de validación.
- Una métrica útil para el negocio: la métrica principal es la proporción de retrasos detectados cuando el equipo solo puede revisar el 10% de los pedidos. Con 7.8% de pedidos tardíos, la exactitud sería engañosa, así que también reporto AUC-PR, y AUC-ROC como referencia.

## Estructura del repositorio

```
├── sql/
│   ├── 01_create_raw_tables.sql    # esquema de datos crudos (9 tablas)
│   ├── 02_load_raw.sql             # carga de los CSV
│   ├── 03_star_schema.sql          # esquema analítico: dimensiones, hechos y validaciones de integridad
│   ├── 04_analysis.sql             # preguntas de negocio (CTE, funciones de ventana)
│   └── 05_export_model_base.sql    # exportaciones para Python y Power BI
├── notebooks/
│   ├── 01_eda.ipynb
│   ├── 02_features.ipynb
│   └── 03_model.ipynb
├── src/
│   ├── features.py                 # construcción de variables
│   ├── export_powerbi.py           # genera las tablas de Power BI
│   └── plot_style.py
├── powerbi/                        # modelo de datos, medidas DAX, páginas del reporte y validación
├── reports/
│   ├── model_metrics.json          # configuración y resultados de los experimentos
│   ├── figures/
│   └── sql_results/                # resultados de 04_analysis.sql
├── data/                           # los datos crudos no se versionan; ver data/README.md
└── assets/
```

## Cómo reproducirlo

Se necesita PostgreSQL 16+ y Python 3.11+.

```bash
pip install -r requirements.txt

# 1. Datos (ver data/README.md)
git clone --depth 1 https://github.com/olist/work-at-olist-data.git /tmp/olist
cp /tmp/olist/datasets/*.csv data/raw/

# 2. Base de datos
createdb olist
psql -d olist -f sql/01_create_raw_tables.sql
psql -d olist -v data_dir="$PWD/data/raw" -f sql/02_load_raw.sql
psql -d olist -f sql/03_star_schema.sql
psql -d olist -v out_dir="$PWD/reports/sql_results" -f sql/04_analysis.sql
psql -d olist -v out_dir="$PWD/data/processed" -f sql/05_export_model_base.sql

# 3. Notebooks en orden y después las tablas de Power BI
jupyter nbconvert --to notebook --execute --inplace notebooks/0*.ipynb
python src/export_powerbi.py
```

El notebook del modelo tarda unos 3 minutos en una laptop. Todas las semillas aleatorias están fijas.

## Limitaciones

- Los datos solo incluyen compras concretadas, así que no puedo medir cuántas ventas costaría una fecha prometida más larga. Por eso la recomendación es una prueba A/B.
- Los datos terminan en agosto de 2018 y reflejan el marketplace de Olist en ese momento.
- La relación entre retrasos y reseñas negativas es correlacional: los pedidos tardíos y los puntuales también pueden diferir en otras cosas.

## Datos

[Brazilian E-Commerce Public Dataset by Olist](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce), unos 100 mil pedidos de 2016 a 2018, publicado por Olist.

## Autor

Carlos Daniel Torres Pillado, analista de datos con formación en estadística aplicada. Chihuahua, México.

- GitHub: [@cdtorrespi](https://github.com/cdtorrespi)
- Correo: [cdtorres.pi@gmail.com](mailto:cdtorres.pi@gmail.com)
