# Dashboard de Power BI

El reporte tiene tres páginas, **Ejecutiva**, **Logística** y **Riesgo**, y se alimenta de las tablas que generan los scripts del proyecto.

## Datos

Desde la raíz del repositorio:

```bash
psql -d olist -v out_dir="$PWD/data/processed" -f sql/05_export_model_base.sql
# ejecutar notebooks/02_features.ipynb y notebooks/03_model.ipynb
python src/export_powerbi.py
```

El script deja estas tablas en `data/processed/powerbi/`:

| Tabla | Grano | Filas |
|---|---|---:|
| `fact_orders` | pedido (compras de enero de 2017 a agosto de 2018) | 99,092 |
| `risk_orders` | pedido del periodo de prueba (abril a agosto de 2018) con su riesgo | 32,453 |
| `dim_customer` | cliente | 99,092 |
| `dim_seller` | vendedor | 3,095 |
| `dim_product` | producto | 32,951 |
| `dim_date` | día (tabla calculada en DAX) | 608 |

En Power BI, la carpeta de los CSV se define en el parámetro de Power Query `DataFolder`, que se cambia en Transformar datos → Administrar parámetros. La ruta debe terminar en `\`. Cada tabla se carga con `Csv.Document` y tipos de datos explícitos.

## Modelo de datos

Es un esquema de constelación: dos tablas de hechos, `fact_orders` (todos los pedidos) y `risk_orders` (pedidos del periodo de prueba con su riesgo), comparten las dimensiones de fecha, cliente y vendedor. Gracias a eso, un mismo filtro de fecha o de estado actúa sobre las dos.

Todas las relaciones son de uno a muchos, de la dimensión al hecho, y filtran en una sola dirección para que no haya caminos ambiguos entre las dos tablas de hechos.

```
dim_date[Date]              1 ──< fact_orders[purchase_date]
dim_customer[customer_id]   1 ──< fact_orders[customer_id]
dim_seller[seller_id]       1 ──< fact_orders[seller_id]
dim_product[product_id]     1 ──< fact_orders[product_id]

dim_date[Date]              1 ──< risk_orders[purchase_date]
dim_customer[customer_id]   1 ──< risk_orders[customer_id]
dim_seller[seller_id]       1 ──< risk_orders[seller_id]
```

`dim_date` es una tabla calculada, marcada como tabla de fechas para que funcionen las funciones de inteligencia de tiempo:

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

Las llaves y las columnas que no se usan en visuales están ocultas. Las 26 medidas están en [`measures.dax`](measures.dax), agrupadas en cuatro carpetas: Ingresos, Logística, Calificación y Riesgo.

## Validación

Comparé cada medida con la misma cifra calculada en PostgreSQL y todas coinciden. En [`validation.md`](validation.md) está la tabla completa, junto con un error de DAX que encontré en el proceso y cómo lo corregí.

## Páginas

Las tres páginas miden 1280 × 720 px y comparten la misma estructura: título, subtítulo y un filtro de fecha de compra en la esquina superior derecha. La paleta es sobria: azul `#2A78D6` para la serie principal, naranja `#EB6834` para retrasos y alertas, y aqua `#1BAF7A` como segunda serie de comparación.

**Ejecutiva.** Arriba, cuatro tarjetas: ingresos (GMV), pedidos, % a tiempo y calificación promedio. Debajo, dos gráficos con el mismo eje de meses: los ingresos por mes y el % de pedidos no a tiempo. Puse estas dos series en gráficos separados y no en uno combinado de dos ejes, porque con dos escalas en el mismo gráfico la relación visual entre ellas depende de cómo se ajusten los ejes. A la derecha, la calificación promedio según cómo terminó la entrega y una tarjeta con el impacto de los retrasos: reseñas negativas extra, % de reseñas negativas, días de retraso promedio y ticket promedio.

**Logística.** El % de pedidos no a tiempo por estado del cliente, ordenado de mayor a menor. Usé barras en lugar de un mapa porque comparan los 27 estados con más precisión y no dependen del servicio de mapas de Power BI. A la derecha, la evolución del plazo prometido contra el real y una tabla con los vendedores que más pedidos entregaron tarde.

**Riesgo.** Cuatro tarjetas con el resultado de la alerta en el periodo de prueba: pedidos marcados, % de retrasos capturados, precisión y tasa base. Dos filtros, por estado del cliente y del vendedor, y una tabla con todos los pedidos ordenados del colchón más corto al más amplio, con su probabilidad de retraso y el resultado real.

La alerta marca un pedido cuando su colchón (días prometidos ÷ días que tardó su ruta en los últimos 90 días) queda por debajo del percentil 10 de los 30 días anteriores. La probabilidad de la tabla viene de la regresión logística, que sirve como referencia.

## Definición del reporte

La carpeta [`report/`](report/) contiene las tres páginas en formato PBIR: un `page.json` por página y un `visual.json` por visual, con su posición, campos y formato. Para usarlas en otro archivo:

1. Guarda el archivo como proyecto de Power BI (Archivo → Guardar como → *Power BI project files (.pbip)*) y cierra Power BI.
2. Copia `report/pages/` sobre `<proyecto>.Report/definition/pages/`.
3. Vuelve a abrir el `.pbip`.
