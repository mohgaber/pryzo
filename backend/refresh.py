"""Refresh job for Pryzo: re-check store prices, one pass.

Loads every product that has ``product_urls``, re-fetches each store page
via :func:`crawler.fetch_price`, and inserts a new ``PriceRecord`` for every
successful fetch. Failed/blocked fetches are counted and reported -- no
price is ever invented to fill a gap.

Run once::

    python refresh.py

Meant to run on a schedule (e.g. cron every 30 minutes)::

    */30 * * * * cd /path/to/pryzo/backend && .venv/bin/python refresh.py

Only real product page URLs are refreshed. Search-result URLs (Jumia
``/catalog/?q=...``, Amazon ``/s?k=...``) are SKIPPED on purpose: a search
page shows many products, so the first price on it is usually not this
product's price. Verified 2026-11-25 -- an Amazon search for "iPhone 15"
first shows a 427.50 EGP accessory, and "AirPods Pro" a 166.25 EGP one.
Storing those as the product's price would be wrong, so refresh refuses
them. Swap a search URL for the verified product page URL to enable
refreshing for that store.
"""

from __future__ import annotations

from sqlalchemy import func

from models import (
    InstallmentPlan,
    PriceAlert,
    PriceRecord,
    Product,
    SessionLocal,
    Store,
    StoreShipping,
    _utcnow,
    init_db,
)
from crawler import fetch_price

# URL patterns that are search-result pages, not a single product page.
# Refreshing these would store some other listing's price as this
# product's price, so they are skipped (see module docstring).
SEARCH_URL_MARKERS = ("/catalog/?q=", "/catalog/?", "/s?k=", "/s?")


def _is_search_url(url: str) -> bool:
    return any(marker in url for marker in SEARCH_URL_MARKERS)


def _current_lowest_price(db, product_id: int) -> float | None:
    """Lowest LIVE price among the latest PriceRecord per store for a
    product. SAMPLE records (``is_sample=True``) are excluded, so a
    sample price can never trigger an alert."""
    sub = (
        db.query(
            PriceRecord.store_id,
            func.max(PriceRecord.fetched_at).label("latest"),
        )
        .filter(
            PriceRecord.product_id == product_id,
            PriceRecord.is_sample.is_(False),
        )
        .group_by(PriceRecord.store_id)
        .subquery()
    )
    value = (
        db.query(func.min(PriceRecord.price))
        .join(
            sub,
            (PriceRecord.store_id == sub.c.store_id)
            & (PriceRecord.fetched_at == sub.c.latest),
        )
        .filter(
            PriceRecord.product_id == product_id,
            PriceRecord.is_sample.is_(False),
        )
        .scalar()
    )
    return float(value) if value is not None else None


def _check_alerts(db) -> None:
    """Mark PRICE alerts triggered when the product's current lowest price is
    at or below the alert's target price. Sticky: once triggered, an
    alert stays triggered (a later price rise does not un-trigger it).
    Back-in-stock alerts are NOT handled here (they have no target
    price); see _trigger_back_in_stock()."""
    alerts = (
        db.query(PriceAlert)
        .filter(PriceAlert.active.is_(True), PriceAlert.alert_type == "price")
        .all()
    )
    newly = 0
    for alert in alerts:
        if alert.triggered:
            continue
        lowest = _current_lowest_price(db, alert.product_id)
        if lowest is not None and alert.target_price is not None and lowest <= alert.target_price:
            alert.triggered = True
            newly += 1
            print(
                f"ALERT triggered: product_id={alert.product_id} "
                f"lowest={lowest} EGP <= target={alert.target_price} EGP"
            )
    if newly:
        db.commit()
        print(f"Alerts newly triggered: {newly}")
    else:
        print("Alerts checked: none newly triggered")


def _latest_live_record(db, product_id: int, store_id: int) -> PriceRecord | None:
    """Latest LIVE PriceRecord for one product/store pair (or None)."""
    return (
        db.query(PriceRecord)
        .filter(
            PriceRecord.product_id == product_id,
            PriceRecord.store_id == store_id,
            PriceRecord.is_sample.is_(False),
        )
        .order_by(PriceRecord.fetched_at.desc())
        .first()
    )


def _trigger_back_in_stock(
    db, product_id: int, store_slug: str, was_in_stock: bool | None, now_in_stock: bool
) -> int:
    """Phase 3: mark matching active back_in_stock alerts triggered when
    a store goes from out-of-stock to in-stock. ``was_in_stock`` is the
    previous latest LIVE record's flag (None = no previous live record,
    so no transition). An alert matches when it is for this product and
    its store_slug is NULL (any store) or equals this store. Sticky:
    once triggered it stays triggered. Returns how many alerts fired."""
    if was_in_stock is not False or not now_in_stock:
        return 0
    alerts = (
        db.query(PriceAlert)
        .filter(
            PriceAlert.active.is_(True),
            PriceAlert.alert_type == "back_in_stock",
            PriceAlert.product_id == product_id,
            PriceAlert.triggered.is_(False),
        )
        .all()
    )
    fired = 0
    for alert in alerts:
        if alert.store_slug is not None and alert.store_slug != store_slug:
            continue
        alert.triggered = True
        fired += 1
        print(
            f"BACK-IN-STOCK alert triggered: product_id={product_id} "
            f"store={store_slug} alert_id={alert.id}"
        )
    return fired


def _store_extras(
    db, product_id: int, store_id: int, result: dict
) -> None:
    """Phase 3: persist the installment/shipping extras from a live
    fetch. Installment: the previous LIVE plan for this product/store
    is replaced (sample plans are left alone as fallback); the compare
    endpoint always shows the latest plan, live preferred. Shipping:
    the store's row is replaced wholesale with exactly what the live
    extraction found -- fields it could not find become NULL, never a
    leftover sample estimate presented as live."""
    plan = result.get("installment")
    if plan:
        db.query(InstallmentPlan).filter(
            InstallmentPlan.product_id == product_id,
            InstallmentPlan.store_id == store_id,
            InstallmentPlan.is_sample.is_(False),
        ).delete()
        db.add(InstallmentPlan(
            product_id=product_id,
            store_id=store_id,
            months=plan["months"],
            monthly_amount=plan["monthly_amount"],
            total_amount=plan.get("total_amount"),
            is_sample=False,
        ))
    shipping = result.get("shipping")
    if shipping:
        row = db.query(StoreShipping).filter_by(store_id=store_id).first()
        if row is None:
            row = StoreShipping(store_id=store_id)
            db.add(row)
        row.fee = shipping.get("fee")
        row.free_above = shipping.get("free_above")
        row.delivery_days_min = shipping.get("delivery_days_min")
        row.delivery_days_max = shipping.get("delivery_days_max")
        row.is_sample = False
        row.updated_at = _utcnow()


def _record_live_price(db, product, store, result: dict) -> PriceRecord:
    """Insert one LIVE PriceRecord from a crawler result, running the
    back-in-stock check FIRST (against the previous latest live
    record) and storing any installment/shipping extras. This is the
    single code path refresh() uses per fetch, and the smoke test
    calls it directly with an injected result to prove the
    back-in-stock transition without hitting the network."""
    previous = _latest_live_record(db, product.id, store.id)
    was_in_stock = previous.in_stock if previous is not None else None
    record = PriceRecord(
        product_id=product.id,
        store_id=store.id,
        price=result["price"],
        currency=result.get("currency", "EGP"),
        in_stock=result.get("in_stock", True),
        url=result.get("url"),
        # Live fetch: never a sample price.
        is_sample=False,
    )
    db.add(record)
    db.flush()
    _trigger_back_in_stock(
        db, product.id, store.slug, was_in_stock, record.in_stock
    )
    _store_extras(db, product.id, store.id, result)
    return record


def refresh() -> dict:
    init_db()
    db = SessionLocal()
    checked = updated = failed = skipped = 0
    failures: list[str] = []
    try:
        from models import Product

        products = (
            db.query(Product)
            .filter(Product.product_urls.isnot(None))
            .all()
        )
        stores = {s.slug: s for s in db.query(Store).all()}

        for product in products:
            urls = product.product_urls or {}
            for slug, url in urls.items():
                if not url:
                    continue
                if _is_search_url(url):
                    skipped += 1
                    print(f"SKIP {product.name} @ {slug}: search URL, not a product page")
                    continue
                store = stores.get(slug)
                if store is None:
                    failed += 1
                    failures.append(f"{product.name} @ {slug}: unknown store slug")
                    continue
                checked += 1
                result = fetch_price(slug, url)
                if result is None:
                    failed += 1
                    failures.append(
                        f"{product.name} @ {slug}: fetch failed/blocked "
                        f"(see crawler log for reason)"
                    )
                    continue
                # Back-in-stock check, installment/shipping extras and
                # the live PriceRecord insert all happen in here.
                _record_live_price(db, product, store, result)
                updated += 1
                print(f"OK  {product.name} @ {slug}: {result['price']} EGP")
        db.commit()
        _check_alerts(db)
    finally:
        db.close()

    summary = {"checked": checked, "updated": updated, "failed": failed, "skipped": skipped}
    print(
        f"\nRefresh summary: checked={checked} updated={updated} "
        f"failed={failed} skipped={skipped}"
    )
    for f in failures:
        print(f"  FAILED: {f}")
    return summary


if __name__ == "__main__":
    refresh()
