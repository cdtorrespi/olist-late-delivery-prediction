"""
Feature engineering to predict, AT PURCHASE TIME, whether an order will
not arrive on time.

Core rule against data leakage:
    A feature may only use information that existed at the moment of
    purchase (purchase_ts).

For the history features (seller, route) this requires knowing WHEN the
outcome of each earlier order became known:
    * On-time order -> known when it was delivered (delivered_ts).
    * Late order    -> known when the promised day ended, i.e. at 00:00
                       on the day after estimated_date (even if it was
                       delivered much later).
An earlier order enters another order's history only if its outcome was
already known before the second order was placed.
"""

from __future__ import annotations

import numpy as np
import pandas as pd

# Bayesian prior to smooth rates with few orders: it is equivalent to
# "PRIOR_STRENGTH imaginary orders at the overall late rate".
PRIOR_STRENGTH = 20
# Same idea for historical delivery days (smoothed mean).
DAYS_PRIOR_STRENGTH = 10
# Window for historical delivery days (chosen on validation).
HIST_WINDOW_DAYS = 90

CATEGORICAL_FEATURES = [
    "customer_state",
    "seller_state",
    "main_category",
    "main_payment_type",
]

# Features left out on purpose (see the README): purchase month, the
# platform's absolute order count and the seller's absolute counts. All three
# grow or shift over time, the model uses them to memorize the training
# period, and they make the out-of-time test worse.
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
    """Read the table exported by sql/05_export_model_base.sql."""
    df = pd.read_csv(
        path,
        parse_dates=["purchase_ts", "estimated_date", "delivered_ts"],
        dtype={"customer_state": "string", "seller_state": "string"},
    )
    return df.sort_values("purchase_ts").reset_index(drop=True)


def add_outcome_known_ts(df: pd.DataFrame) -> pd.DataFrame:
    """Moment when each order's outcome (on time / late) became known."""
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
    For each order, the historical late rate of its `key` (seller or route)
    using only orders whose outcome was known before the purchase.

    Solved with merge_asof: the "events" (known outcomes) are accumulated
    per key in the order they became known, and each order takes the last
    running total strictly before its purchase_ts.
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
        allow_exact_matches=False,  # strictly before the purchase
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
    Mean delivery days (purchase -> delivery) for each `key` over the last
    `window_days` days, using only orders ALREADY DELIVERED before the
    purchase. Undelivered orders contribute no days because their actual
    duration is unknown.

    A recent window is used (not the full history) because delivery times
    changed a lot in 2018: with an all-time average, a route that got faster
    would still look slow. The 90-day window was chosen on the validation
    period (see notebooks/03_model.ipynb).

    Implementation: running sums per key, looked up at t (purchase) and at
    t - window; the difference gives the orders delivered within the window.
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
    # Running total of deliveries strictly before the purchase
    upto_now = pd.merge_asof(
        queries.sort_values("purchase_ts"), events[cols],
        left_on="purchase_ts", right_on="delivered_ts", by=key,
        allow_exact_matches=False, direction="backward",
    ).set_index("order_id")
    # Running total of deliveries up to the window start (subtracted)
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
    """How many events fell in the window [t - window, t) for each t (times must be sorted)."""
    t = times.values.astype("datetime64[ns]")
    start = t - pd.Timedelta(window).to_timedelta64()
    return np.searchsorted(t, t, side="left") - np.searchsorted(t, start, side="left")


def build_features(df: pd.DataFrame, cutoff: pd.Timestamp) -> pd.DataFrame:
    """
    Return the DataFrame with every model feature.

    `cutoff` is the start of the period to be evaluated. The smoothing priors
    (overall late rate and mean delivery days) are computed only from
    information known before that date, so nothing leaks from the
    evaluation period.
    """
    out = add_outcome_known_ts(df)
    out["actual_days"] = (
        out["delivered_ts"].dt.normalize() - out["purchase_ts"].dt.normalize()
    ).dt.days
    known_before = out["outcome_known_ts"] < cutoff
    global_rate = out.loc[known_before, TARGET].mean()
    global_mean_days = out.loc[out["delivered_ts"] < cutoff, "actual_days"].mean()

    # --- Direct order features ---------------------------------------
    out["same_state"] = (out["customer_state"] == out["seller_state"]).astype(int)
    out["freight_share"] = out["freight_value"] / (out["items_value"] + out["freight_value"])
    out["purchase_month"] = out["purchase_ts"].dt.month
    out["purchase_weekday"] = out["purchase_ts"].dt.weekday
    out["purchase_hour"] = out["purchase_ts"].dt.hour

    # --- Main seller history -----------------------------------------
    seller_hist = _history_rate(out, "main_seller_id", global_rate, "seller")
    out = out.merge(seller_hist, on="order_id", how="left")

    # Recent seller volume (orders placed with the seller in the previous 30 days)
    out = out.sort_values(["main_seller_id", "purchase_ts"])
    out["seller_orders_last_30d"] = (
        out.groupby("main_seller_id", group_keys=False)["purchase_ts"]
        .apply(lambda s: pd.Series(_rolling_count_before(s, "30D"), index=s.index))
    )
    out = out.sort_values("purchase_ts").reset_index(drop=True)

    # --- Route history: seller state -> customer state ---------------
    out["route"] = out["seller_state"].fillna("NA") + "->" + out["customer_state"].fillna("NA")
    route_hist = _history_rate(out, "route", global_rate, "route")
    out = out.merge(route_hist.drop(columns="route_known_orders"), on="order_id", how="left")

    # --- Buffer in the promised delivery time ------------------------
    # How many days does Olist promise versus how long the route (or the
    # seller) has historically taken? A short buffer is the strongest risk signal.
    out["route_hist_days"] = _history_mean_days(out, "route", global_mean_days)
    out["seller_hist_days"] = _history_mean_days(out, "main_seller_id", global_mean_days)
    out["promise_buffer_route"] = out["promised_days"] - out["route_hist_days"]
    out["promise_buffer_seller"] = out["promised_days"] - out["seller_hist_days"]
    out["promise_ratio"] = out["promised_days"] / out["route_hist_days"]

    # --- Platform load (peaks such as Black Friday) -------------------
    out["platform_orders_last_7d"] = _rolling_count_before(out["purchase_ts"], "7D")
    orders_last_28d = _rolling_count_before(out["purchase_ts"], "28D")
    out["platform_load_ratio"] = out["platform_orders_last_7d"] / np.maximum(orders_last_28d / 4, 1)

    for col in CATEGORICAL_FEATURES:
        out[col] = out[col].fillna("unknown").astype("string")

    return out
