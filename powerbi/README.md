# Dashboard de Power BI

El dashboard tiene tres páginas: **Ejecutiva**, **Logística** y **Riesgo**. Se alimenta de las tablas que generan los scripts del proyecto.

## 1. Datos

Desde la raíz del repositorio:

```bash
psql -d olist -v out_dir="$PWD/data/processed" -f sql/05_export_model_base.sql
# ejecutar notebooks/02_features.ipynb y notebooks/03_model.ipynb
python src/export_powerbi.py
```

Esto deja en `data/processed/powerbi/`:

| Tabla | Grano | Filas |
|---|---|---:|
| `fact_orders` | pedido (compras 2017-01 a 2018-08) | 99,092 |
| `risk_orders` | pedido del periodo de prueba (abr-ago 2018) con su riesgo | 32,453 |
| `dim_customer` | cliente | 99,092 |
| `dim_seller` | vendedor | 3,095 |
| `dim_product` | producto | 32,951 |
| `dim_date` | día (tabla calculada en DAX) | 608 |

Copie esos 5 CSV a una carpeta local. En Power BI, la ruta se define en el parámetro de Power Query **`DataFolder`** (Transformar datos → Administrar parámetros); la ruta debe terminar en `\`. Cada tabla se carga con `Csv.Document(File.Contents(DataFolder & "<tabla>.csv"))` y tipos explícitos.

## 2. Modelo de datos

Modelo estrella con dos tablas de hechos que comparten dimensiones. Todas las relaciones son uno a muchos, con filtro en una sola dirección (de la dimensión al hecho).

```
dim_date[Date]              1 ──< fact_orders[purchase_date]
dim_customer[customer_id]   1 ──< fact_orders[customer_id]
dim_seller[seller_id]       1 ──< fact_orders[seller_id]
dim_product[product_id]     1 ──< fact_orders[product_id]

dim_date[Date]              1 ──< risk_orders[purchase_date]
dim_customer[customer_id]   1 ──< risk_orders[customer_id]
dim_seller[seller_id]       1 ──< risk_orders[seller_id]
```

`dim_date` es una tabla calculada, marcada como tabla de fechas:

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

Las columnas de llaves (`*_id`) y las que no se usan en visuales están ocultas. Las medidas están en `measures.dax`, organizadas en cuatro carpetas: Ingresos, Logística, Calificación y Riesgo.

## 3. Validación contra SQL

Cada medida se comparó con la misma cifra calculada en PostgreSQL. Las 26 coinciden; el detalle, incluido un error de DAX que se encontró y corrigió, está en [`validation.md`](validation.md).

## 4. Diseño de las páginas

Lienzo 16:9 (1280 × 720 px).

### Paleta

| Uso | Color |
|---|---|
| Fondo | `#FCFCFB` |
| Texto principal | `#0B0B0B` |
| Texto secundario | `#52514E` |
| Serie principal | `#2A78D6` (azul) |
| Retrasos / alerta | `#EB6834` (naranja) |
| Comparación | `#1BAF7A` (aqua) |
| Referencia | `#A3A29D` (gris) |

Use una sola fuente (Segoe UI), sin bordes ni sombras en los visuales, títulos alineados a la izquierda en 14 pt y etiquetas en 10 pt.

### Elementos comunes (las tres páginas)

- **Título** (cuadro de texto, x 24, y 16, 900 × 40): nombre de la página en 20 pt negrita.
- **Segmentación de fecha** (x 960, y 16, 296 × 40): `dim_date[Date]`, estilo "Entre". Sincronícela en las tres páginas (Ver → Sincronizar segmentaciones).

### Página 1 · Ejecutiva

| Visual | Posición (x, y, ancho × alto) | Campos |
|---|---|---|
| Tarjeta | 24, 72, 296 × 110 | `[Ingresos (GMV)]` |
| Tarjeta | 336, 72, 296 × 110 | `[Pedidos]` |
| Tarjeta | 648, 72, 296 × 110 | `[% a tiempo]` |
| Tarjeta | 960, 72, 296 × 110 | `[Calificación promedio]` |
| Gráfico de columnas | 24, 198, 816 × 242 | Eje X: `dim_date[year_month]`; valores: `[Ingresos (GMV)]` en azul. Título: "Ingresos por mes" |
| Gráfico de líneas | 24, 456, 816 × 242 | Eje X: `dim_date[year_month]`; valores: `[% no a tiempo]` en naranja, con marcadores y etiquetas de datos solo en el valor máximo. Título: "% de pedidos no a tiempo por mes" |
| Gráfico de barras agrupadas | 856, 198, 400 × 242 | Eje Y: `fact_orders[delivery_status_label]`; valores: `[Calificación promedio]`. Barra "Tarde" y "No entregado" en naranja, el resto en azul. Título: "Calificación según la entrega" |
| Tarjeta de varias filas | 856, 456, 400 × 242 | `[Reseñas negativas por retraso]`, `[% reseñas negativas]`, `[Ticket promedio]`, `[Crecimiento mensual %]` |

**Nota de diseño:** los ingresos y el % no a tiempo van en dos gráficos apilados con el mismo eje X, no en un gráfico combinado de dos ejes. Con dos escalas distintas en un mismo gráfico, la relación visual entre las series depende de cómo se ajusten los ejes y se presta a lecturas equivocadas.

### Página 2 · Logística

| Visual | Posición | Campos |
|---|---|---|
| Gráfico de barras | 24, 84, 560 × 620 | Eje Y: `dim_customer[state]`; valores: `[% no a tiempo]` en naranja, con etiquetas, orden descendente. Título: "% de pedidos no a tiempo por estado del cliente". Se eligieron barras en lugar de un mapa porque comparan 27 estados con más precisión y no dependen del servicio de mapas. |
| Gráfico de líneas | 600, 72, 656 × 300 | Eje X: `dim_date[year_month]`; valores: `[Días prometidos (prom.)]` en azul y `[Días reales (prom.)]` en aqua. Título: "Plazo prometido vs. real" |
| Tabla | 600, 388, 656 × 310 | `dim_seller[seller_id]`, `dim_seller[state]`, `[Pedidos con resultado]`, `[Pedidos no a tiempo]`, `[% no a tiempo]`, `[Calificación promedio]`. Filtro del visual: `[Pedidos con resultado]` ≥ 50. Orden: `[Pedidos no a tiempo]` descendente. Formato condicional en `[% no a tiempo]`: barras de datos naranjas. Título: "Vendedores con más pedidos tarde" |

### Página 3 · Riesgo (abr-ago 2018)

| Visual | Posición | Campos |
|---|---|---|
| Tarjeta | 24, 72, 296 × 110 | `[Pedidos marcados]` |
| Tarjeta | 336, 72, 296 × 110 | `[% retrasos capturados]` |
| Tarjeta | 648, 72, 296 × 110 | `[Precisión de la alerta]` |
| Tarjeta | 960, 72, 296 × 110 | `[Tasa de retraso (prueba)]` (como referencia) |
| Segmentación | 24, 198, 296 × 240 | `dim_customer[state]` (lista con búsqueda) |
| Segmentación | 24, 454, 296 × 244 | `dim_seller[state]` |
| Tabla | 336, 198, 920 × 500 | `risk_orders[order_id]`, `risk_orders[purchase_date]`, `risk_orders[route]`, `risk_orders[promised_days]`, `risk_orders[route_hist_days]`, `risk_orders[promise_ratio]`, `risk_orders[late_probability]`, `risk_orders[flag_high_risk]`, `risk_orders[delivery_status_label]`. Orden: `promise_ratio` ascendente. Formato condicional: `promise_ratio` con fondo de naranja (bajo) a blanco (alto); `late_probability` con barras de datos. Título: "Pedidos ordenados por riesgo (colchón más corto primero)" |

Agregue debajo del título de la página 3 un cuadro de texto en 10 pt, color `#52514E`:

> Alerta = colchón del plazo (días prometidos ÷ días que tardó la ruta en los últimos 90 días) por debajo del percentil 10 de los 30 días previos. La probabilidad viene de una regresión logística de referencia.

## 5. Definición del reporte

La carpeta [`report/`](report/) contiene las 3 páginas en formato PBIR (Power BI Project): un `page.json` por página y un `visual.json` por visual, con posición, campos y formato. Para usarla:

1. Guarde su archivo como proyecto (Archivo → Guardar como → *Power BI project files (.pbip)*).
2. Cierre Power BI.
3. Copie `report/pages/` sobre `<proyecto>.Report/definition/pages/`.
4. Vuelva a abrir el `.pbip`.

## 6. Publicar

Power BI Desktop → Archivo → Exportar → PDF para una versión estática. Si tiene una cuenta laboral, también puede usar Publicar → "Publicar en la web".
