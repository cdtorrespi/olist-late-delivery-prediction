"""
Prepara las tablas que importa Power BI: el modelo dimensional y el riesgo de cada pedido del periodo de prueba.

Entrada: los CSV que generan sql/05_export_model_base.sql y
notebooks/03_model.ipynb en data/processed/.
Salida:  data/processed/powerbi/*.csv

Uso (desde la raíz del repositorio):
    python src/export_powerbi.py
"""

from pathlib import Path

import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
SRC = ROOT / "data" / "processed"
OUT = SRC / "powerbi"

STATUS_LABELS = {
    "on_time": "A tiempo",
    "late": "Tarde",
    "not_delivered": "No entregado",
    "canceled": "Cancelado",
    "other": "En proceso",
}
STATE_NAMES = {
    "AC": "Acre", "AL": "Alagoas", "AM": "Amazonas", "AP": "Amapá", "BA": "Bahia", "CE": "Ceará",
    "DF": "Distrito Federal", "ES": "Espírito Santo", "GO": "Goiás", "MA": "Maranhão",
    "MG": "Minas Gerais", "MS": "Mato Grosso do Sul", "MT": "Mato Grosso", "PA": "Pará",
    "PB": "Paraíba", "PE": "Pernambuco", "PI": "Piauí", "PR": "Paraná", "RJ": "Rio de Janeiro",
    "RN": "Rio Grande do Norte", "RO": "Rondônia", "RR": "Roraima", "RS": "Rio Grande do Sul",
    "SC": "Santa Catarina", "SE": "Sergipe", "SP": "São Paulo", "TO": "Tocantins",
}


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)

    fact = pd.read_csv(SRC / "pbi_fact_orders.csv")
    fact["delivery_status_label"] = fact["delivery_status"].map(STATUS_LABELS)
    fact["is_late"] = fact["is_late"].astype("Int64")
    fact.to_csv(OUT / "fact_orders.csv", index=False)

    customers = pd.read_csv(SRC / "pbi_dim_customer.csv")
    customers = customers[customers.customer_id.isin(fact.customer_id)]
    customers["state_name"] = customers["state"].map(STATE_NAMES)
    customers["country"] = "Brazil"
    customers.to_csv(OUT / "dim_customer.csv", index=False)

    sellers = pd.read_csv(SRC / "pbi_dim_seller.csv")
    sellers["state_name"] = sellers["state"].map(STATE_NAMES)
    sellers.to_csv(OUT / "dim_seller.csv", index=False)

    products = pd.read_csv(SRC / "pbi_dim_product.csv")
    products.to_csv(OUT / "dim_product.csv", index=False)

    risk = pd.read_csv(SRC / "test_predictions.csv")
    risk = risk.merge(fact[["order_id", "customer_id", "delivery_status_label"]], on="order_id", how="left")
    risk = risk[[
        "order_id", "customer_id", "seller_id", "purchase_date", "customer_state", "seller_state", "route",
        "promised_days", "route_hist_days", "promise_ratio", "late_probability", "risk_percentile",
        "flag_high_risk", "is_late", "delivery_status_label",
    ]]
    risk["route_hist_days"] = risk["route_hist_days"].round(1)
    risk["promise_ratio"] = risk["promise_ratio"].round(3)
    risk.to_csv(OUT / "risk_orders.csv", index=False)

    for f in sorted(OUT.glob("*.csv")):
        print(f"{f.name:20s} {sum(1 for _ in open(f, encoding='utf-8')) - 1:>8,} filas")


if __name__ == "__main__":
    main()
