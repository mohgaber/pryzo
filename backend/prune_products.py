"""Prune discontinued products from the Pryzo DB (one-off, 2026-11-26).

Mohamed's decision: drop the 4 products that have no live price anywhere
(they were discontinued on all 7 stores) and keep only the 5 with live
prices. Run once on Railway via a temporary start command, e.g.
`python prune_products.py`, then restore the normal start command.

Deletes, for each named product:
  - its InstallmentPlan rows first (no cascade from Product to plans),
  - then the Product row itself (SQLAlchemy cascade="all, delete-orphan"
    removes its PriceRecords, PriceAlerts and WatchlistItems).

Safe to re-run: a product that is already gone is reported, not an error.
Only the 4 names below are ever touched.
"""

from models import InstallmentPlan, Product, SessionLocal

# Discontinued on all 7 stores (verified 2026-11-26 by on-site search of
# Noon / Dream 2000 / Vodafone / Carrefour — only the newer generations
# are listed now: S25/S26, A56/A57, Redmi Note 15/17, LG NU85-series).
PRUNE_NAMES = [
    "Samsung Galaxy S24 256GB",
    "Samsung Galaxy A55 5G 256GB",
    'LG 43" 4K UHD Smart TV 43UR78006',
    "Xiaomi Redmi Note 13 256GB",
]


def prune() -> None:
    db = SessionLocal()
    try:
        for name in PRUNE_NAMES:
            product = db.query(Product).filter_by(name=name).first()
            if product is None:
                print(f"Already gone: {name}")
                continue
            plans = (
                db.query(InstallmentPlan)
                .filter_by(product_id=product.id)
                .delete(synchronize_session=False)
            )
            prices = len(product.price_records)
            alerts = len(product.alerts)
            watch = len(product.watchlist_items)
            db.delete(product)
            db.commit()
            print(
                f"Deleted: {name} (id {product.id}; "
                f"{prices} price records, {plans} installment plans, "
                f"{alerts} alerts, {watch} watchlist items)"
            )
        remaining = [p.name for p in db.query(Product).order_by(Product.id)]
        print(f"Products left ({len(remaining)}): {remaining}")
    finally:
        db.close()


if __name__ == "__main__":
    prune()
