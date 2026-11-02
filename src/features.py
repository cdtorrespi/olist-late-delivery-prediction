"""
Construcción de variables para predecir, AL MOMENTO DE LA COMPRA, si un
pedido no llegará a tiempo.

Regla central contra la fuga de datos:
    Una variable solo puede usar información que existía en el instante
    de la compra (purchase_ts).

Para las variables de historial (vendedor, ruta) eso exige saber CUÁNDO
se conoció el resultado de cada pedido anterior:
    * Pedido a tiempo  -> se supo al entregarse (delivered_ts).
    * Pedido tardío    -> se supo al terminar el día prometido, es decir,
                          a las 00:00 del día siguiente a estimated_date
                          (aunque se haya entregado mucho después).
Un pedido anterior entra al historial de otro solo si su resultado ya se
conocía antes de la compra del segundo.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

# Prior bayesiano para suavizar tasas con pocos pedidos: equivale a
# "PRIOR_STRENGTH pedidos imaginarios con la tasa global de retraso".
PRIOR_STRENGTH = 20
# Lo mismo para los días de entrega históricos (promedio suavizado).
DAYS_PRIOR_STRENGTH = 10
# Ventana para los días de entrega históricos (elegida en validación).
HIST_WINDOW_DAYS = 90

CATEGORICAL_FEATURES = [
    "customer_state",
    "seller_state",
    "main_category",
    "main_payment_type",
]

# Variables descartadas a propósito (ver reports/reporte_tecnico.pdf): el mes de compra,
# el número absoluto de pedidos de la plataforma y los conteos absolutos del
# vendedor. Las tres crecen o cambian con el tiempo, el modelo las usa para
# memorizar la época del entrenamiento y empeoran la prueba fuera de periodo.
NUMERIC_FEATURES = [
    "promised_days",
    "route_hist_days",
    "seller_hist_days",
    "promise_buffer_route",
    "promise_buffer_seller",
    "promise_ratio",
    "max_distance_km",
    "same_state",
    "n_items",
    "n_sellers",
    "items_value",
    "freight_value",
    "freight_share",
    "total_weight_g",
    "total_volume_cm3",
    "max_installments",
    "main_photos_qty",
    "purchase_weekday",
    "purchase_hour",
    "seller_late_rate_hist",
    "route_late_rate_hist",
    "platform_load_ratio",
]

FEATURES = NUMERIC_FEATURES + CATEGORICAL_FEATURES
TARGET = "is_late"


def load_model_base(path: str) -> pd.DataFrame:
    """Lee la tabla exportada por sql/05_export_model_base.sql."""
    df = pd.read_csv(
        path,
        parse_dates=["purchase_ts", "estimated_date", "delivered_ts"],
        dtype={"customer_state": "string", "seller_state": "string"},
    )
    return df.sort_values("purchase_ts").reset_index(drop=True)


def add_outcome_known_ts(df: pd.DataFrame) -> pd.DataFrame:
    """Instante en que el resultado (a tiempo / tarde) de cada pedido se volvió conocido."""
    out = df.copy()
    end_of_promised_day = out["estimated_date"] + pd.Timedelta(days=1)
    out["outcome_known_ts"] = np.where(
        out[TARGET] == 1, end_of_promised_day, out["delivered_ts"]
    )
    out["outcome_known_ts"] = pd.to_datetime(out["outcome_known_ts"])
    return out


def _history_rate(
    df: pd.DataFrame, key: str, global_rate: float, prefix: str
) -> pd.DataFrame:
    """
    Para cada pedido, tasa de retraso histórica de su `key` (vendedor o ruta)
    usando solo pedidos cuyo resultado se conocía antes de la compra.

    Se resuelve con merge_asof: los "eventos" (resultados conocidos) se
    acumulan por clave en el orden en que se conocieron, y cada pedido toma
    el último acumulado estrictamente anterior a su purchase_ts.
    """
    events = (
        df[[key, "outcome_known_ts", TARGET]]
        .dropna(subset=[key])
        .sort_values("outcome_known_ts")
        .copy()
    )
    events["cum_known"] = events.groupby(key).cumcount() + 1
    events["cum_late"] = events.groupby(key)[TARGET].cumsum()

    queries = df[["order_id", key, "purchase_ts"]].sort_values("purchase_ts")
    merged = pd.merge_asof(
        queries,
        events[[key, "outcome_known_ts", "cum_known", "cum_late"]],
        left_on="purchase_ts",
        right_on="outcome_known_ts",
        by=key,
        allow_exact_matches=False,  # estrictamente antes de la compra
        direction="backward",
    )
    known = merged["cum_known"].fillna(0)
    late = merged["cum_late"].fillna(0)
    merged[f"{prefix}_late_rate_hist"] = (late + PRIOR_STRENGTH * global_rate) / (
        known + PRIOR_STRENGTH
    )
    merged[f"{prefix}_known_orders"] = known
    return merged[["order_id", f"{prefix}_late_rate_hist", f"{prefix}_known_orders"]]


def _history_mean_days(
    df: pd.DataFrame, key: str, global_mean_days: float, window_days: int = HIST_WINDOW_DAYS
) -> pd.Series:
    """
    Promedio de días de entrega (compra -> entrega) de cada `key` en los
    últimos `window_days` días, usando solo pedidos YA ENTREGADOS antes de
    la compra. Los pedidos sin entrega no aportan días porque su duración
    real no se conoce.

    Se usa una ventana reciente (no todo el historial) porque los tiempos de
    entrega cambiaron mucho en 2018: con el promedio acumulado, una ruta que
    se volvió más rápida seguiría pareciendo lenta. La ventana de 90 días se
    eligió en el periodo de validación (ver notebooks/03_model.ipynb).

    Implementación: sumas acumuladas por clave, consultadas en t (compra) y
    en t - ventana; la resta da los pedidos entregados dentro de la ventana.
    """
    events = (
        df.loc[df["delivered_ts"].notna(), [key, "delivered_ts", "actual_days"]]
        .sort_values("delivered_ts")
        .copy()
    )
    events["cum_n"] = events.groupby(key).cumcount() + 1
    events["cum_days"] = events.groupby(key)["actual_days"].cumsum()
    cols = [key, "delivered_ts", "cum_n", "cum_days"]

    queries = df[["order_id", key, "purchase_ts"]]
    # Acumulado de entregas estrictamente antes de la compra
    upto_now = pd.merge_asof(
        queries.sort_values("purchase_ts"), events[cols],
        left_on="purchase_ts", right_on="delivered_ts", by=key,
        allow_exact_matches=False, direction="backward",
    ).set_index("order_id")
    # Acumulado de entregas hasta el inicio de la ventana (se resta)
    window_start = queries.assign(window_start=queries["purchase_ts"] - pd.Timedelta(days=window_days))
    upto_start = pd.merge_asof(
        window_start.sort_values("window_start"), events[cols],
        left_on="window_start", right_on="delivered_ts", by=key,
        allow_exact_matches=True, direction="backward",
    ).set_index("order_id").reindex(upto_now.index)

    n = upto_now["cum_n"].fillna(0) - upto_start["cum_n"].fillna(0)
    total_days = upto_now["cum_days"].fillna(0) - upto_start["cum_days"].fillna(0)
    mean_days = (total_days + DAYS_PRIOR_STRENGTH * global_mean_days) / (n + DAYS_PRIOR_STRENGTH)
    return df["order_id"].map(mean_days)


def _rolling_count_before(times: pd.Series, window: str) -> np.ndarray:
    """Cuántos eventos ocurrieron en la ventana [t - window, t) para cada t (times ordenados)."""
    t = times.values.astype("datetime64[ns]")
    start = t - pd.Timedelta(window).to_timedelta64()
    return np.searchsorted(t, t, side="left") - np.searchsorted(t, start, side="left")


def build_features(df: pd.DataFrame, cutoff: pd.Timestamp) -> pd.DataFrame:
    """
    Devuelve el DataFrame con todas las variables del modelo.

    `cutoff` es el inicio del periodo que se va a evaluar. Los priors de
    suavizado (tasa global de retraso y días promedio de entrega) se calculan
    solo con información conocida antes de esa fecha, para no filtrar nada
    del periodo de evaluación.
    """
    out = add_outcome_known_ts(df)
    out["actual_days"] = (
        out["delivered_ts"].dt.normalize() - out["purchase_ts"].dt.normalize()
    ).dt.days
    known_before = out["outcome_known_ts"] < cutoff
    global_rate = out.loc[known_before, TARGET].mean()
    global_mean_days = out.loc[out["delivered_ts"] < cutoff, "actual_days"].mean()

    # --- Variables directas del pedido -------------------------------
    out["same_state"] = (out["customer_state"] == out["seller_state"]).astype(int)
    out["freight_share"] = out["freight_value"] / (out["items_value"] + out["freight_value"])
    out["purchase_month"] = out["purchase_ts"].dt.month
    out["purchase_weekday"] = out["purchase_ts"].dt.weekday
    out["purchase_hour"] = out["purchase_ts"].dt.hour

    # --- Historial del vendedor principal ----------------------------
    seller_hist = _history_rate(out, "main_seller_id", global_rate, "seller")
    out = out.merge(seller_hist, on="order_id", how="left")

    # Volumen reciente del vendedor (compras de sus pedidos en los 30 días previos)
    out = out.sort_values(["main_seller_id", "purchase_ts"])
    out["seller_orders_last_30d"] = (
        out.groupby("main_seller_id", group_keys=False)["purchase_ts"]
        .apply(lambda s: pd.Series(_rolling_count_before(s, "30D"), index=s.index))
    )
    out = out.sort_values("purchase_ts").reset_index(drop=True)

    # --- Historial de la ruta estado vendedor -> estado cliente -------
    out["route"] = out["seller_state"].fillna("NA") + "->" + out["customer_state"].fillna("NA")
    route_hist = _history_rate(out, "route", global_rate, "route")
    out = out.merge(route_hist.drop(columns="route_known_orders"), on="order_id", how="left")

    # --- Colchón del plazo prometido ---------------------------------
    # ¿Cuántos días promete Olist contra lo que históricamente tarda la ruta
    # (o el vendedor)? Un colchón corto es la señal de riesgo más fuerte.
    out["route_hist_days"] = _history_mean_days(out, "route", global_mean_days)
    out["seller_hist_days"] = _history_mean_days(out, "main_seller_id", global_mean_days)
    out["promise_buffer_route"] = out["promised_days"] - out["route_hist_days"]
    out["promise_buffer_seller"] = out["promised_days"] - out["seller_hist_days"]
    out["promise_ratio"] = out["promised_days"] / out["route_hist_days"]

    # --- Carga de la plataforma (picos como Black Friday) ------------
    out["platform_orders_last_7d"] = _rolling_count_before(out["purchase_ts"], "7D")
    orders_last_28d = _rolling_count_before(out["purchase_ts"], "28D")
    out["platform_load_ratio"] = out["platform_orders_last_7d"] / np.maximum(orders_last_28d / 4, 1)

    for col in CATEGORICAL_FEATURES:
        out[col] = out[col].fillna("unknown").astype("string")

    return out
