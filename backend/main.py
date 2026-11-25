"""Pryzo API -- FastAPI backend for the Pryzo price-comparison app.

Run locally::

    uvicorn main:app --reload --port 8000

Docs: http://localhost:8000/docs

NOTE: prices seeded by seed.py are SAMPLE prices, not live store prices.
Live prices are collected by refresh.py via crawler.fetch_price().
"""

from __future__ import annotations

import logging
import os
import secrets
import threading
from datetime import datetime, timedelta, timezone

from fastapi import Depends, FastAPI, Header, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
from sqlalchemy import func
from sqlalchemy.orm import Session

from models import (
    Coupon,
    InstallmentPlan,
    PriceAlert,
    PriceRecord,
    Product,
    Store,
    StoreShipping,
    WatchlistItem,
    get_db,
    init_db,
)

from contextlib import asynccontextmanager


log = logging.getLogger("pryzo.api")
logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    # Log which database is in use -- scheme only, never the URL itself
    # (it contains the password). SQLite means "local-dev fallback":
    # on Render, DATABASE_URL must point at Postgres.
    db_url = os.environ.get("DATABASE_URL", "")
    if db_url.startswith("postgres"):
        log.info("Pryzo API starting: database=PostgreSQL, tables ready")
    elif db_url:
        log.info(
            "Pryzo API starting: database=%s, tables ready",
            db_url.split("://", 1)[0],
        )
    else:
        log.info(
            "Pryzo API starting: database=SQLite (local-dev fallback), "
            "tables ready"
        )
    if not os.environ.get("REFRESH_TOKEN"):
        log.warning(
            "REFRESH_TOKEN is not set: POST /admin/refresh is disabled "
            "(returns 503 until the env var is set)"
        )
    yield


app = FastAPI(title="Pryzo API", version="0.1.0", lifespan=lifespan)

# The Flutter app calls this API from phones/emulators: allow all origins.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Request bodies
# ---------------------------------------------------------------------------

class WatchlistCreate(BaseModel):
    product_id: int


class AlertCreate(BaseModel):
    product_id: int
    # Required for 'price' alerts, optional (ignored) for
    # 'back_in_stock' alerts.
    target_price: float | None = Field(default=None, gt=0)
    alert_type: str = "price"
    # Optional: only this store's stock matters (back_in_stock only).
    store_slug: str | None = None


class CouponCreate(BaseModel):
    store_slug: str
    code: str = Field(min_length=1)
    discount_type: str  # 'percent' | 'fixed'
    discount_value: float = Field(gt=0)
    min_order: float | None = Field(default=None, ge=0)
    expires_at: datetime | None = None


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _latest_prices(db: Session, product_id: int) -> list[PriceRecord]:
    """Latest LIVE PriceRecord per store for a product (cheapest first).

    SAMPLE records (``is_sample=True``, from seed.py) are excluded: a
    sample price must never be shown as a store's price or as the
    cheapest offer.
    """
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
    rows = (
        db.query(PriceRecord)
        .join(
            sub,
            (PriceRecord.store_id == sub.c.store_id)
            & (PriceRecord.fetched_at == sub.c.latest),
        )
        .filter(
            PriceRecord.product_id == product_id,
            PriceRecord.is_sample.is_(False),
        )
        .order_by(PriceRecord.price.asc())
        .all()
    )
    return rows


def _lowest_price(db: Session, product_id: int) -> float | None:
    """Lowest LIVE price for a product (samples excluded). None when
    the product has no live price record yet."""
    value = (
        db.query(func.min(PriceRecord.price))
        .filter(
            PriceRecord.product_id == product_id,
            PriceRecord.is_sample.is_(False),
        )
        .scalar()
    )
    return float(value) if value is not None else None


def _product_summary(db: Session, product: Product) -> dict:
    return {
        "id": product.id,
        "name": product.name,
        "brand": product.brand,
        "category": product.category,
        "image_url": product.image_url,
        "lowest_price": _lowest_price(db, product.id),
        "stores_count": (
            db.query(func.count(func.distinct(PriceRecord.store_id)))
            .filter(
                PriceRecord.product_id == product.id,
                PriceRecord.is_sample.is_(False),
            )
            .scalar()
        ),
    }


def _latest_installment(
    db: Session, product_id: int, store_id: int
) -> InstallmentPlan | None:
    """Latest installment plan for a product/store, LIVE preferred:
    the newest live plan if one exists, else the newest sample plan
    (a sample plan is an estimate only -- flagged via is_sample)."""
    for live_only in (True, False):
        plan = (
            db.query(InstallmentPlan)
            .filter(
                InstallmentPlan.product_id == product_id,
                InstallmentPlan.store_id == store_id,
                InstallmentPlan.is_sample.is_(not live_only),
            )
            .order_by(InstallmentPlan.fetched_at.desc())
            .first()
        )
        if plan is not None:
            return plan
    return None


def _price_row(db: Session, rec: PriceRecord) -> dict:
    store = db.get(Store, rec.store_id)
    row = {
        "store": store.name if store else str(rec.store_id),
        "store_slug": store.slug if store else "",
        "price": rec.price,
        "currency": rec.currency,
        "in_stock": rec.in_stock,
        "url": rec.url,
        "fetched_at": rec.fetched_at.isoformat(),
        "is_sample": rec.is_sample,
    }
    # Phase 3: installment plan (live preferred, sample flagged) and
    # shipping for this store; total = price + fee when the fee is
    # known, else null. All new money fields are LIVE unless flagged
    # sample; sample-flagged values are estimates only.
    plan = _latest_installment(db, rec.product_id, rec.store_id)
    shipping = (
        db.query(StoreShipping).filter_by(store_id=rec.store_id).first()
        if store
        else None
    )
    row["installment_monthly"] = plan.monthly_amount if plan else None
    row["installment_months"] = plan.months if plan else None
    row["installment_is_sample"] = bool(plan.is_sample) if plan else False
    fee = shipping.fee if shipping else None
    row["shipping_fee"] = fee
    row["shipping_is_sample"] = bool(shipping.is_sample) if shipping else False
    row["delivery_days_min"] = (
        shipping.delivery_days_min if shipping else None
    )
    row["delivery_days_max"] = (
        shipping.delivery_days_max if shipping else None
    )
    row["total_price"] = round(rec.price + fee, 2) if fee is not None else None
    return row


def _coupon_row(db: Session, coupon: Coupon) -> dict:
    store = db.get(Store, coupon.store_id)
    return {
        "id": coupon.id,
        "store": store.name if store else str(coupon.store_id),
        "store_slug": store.slug if store else "",
        "code": coupon.code,
        "discount_type": coupon.discount_type,
        "discount_value": coupon.discount_value,
        "min_order": coupon.min_order,
        "expires_at": coupon.expires_at.isoformat() if coupon.expires_at else None,
        "is_sample": coupon.is_sample,
        "active": coupon.active,
    }


def _get_product_or_404(db: Session, product_id: int) -> Product:
    product = db.get(Product, product_id)
    if product is None:
        raise HTTPException(status_code=404, detail="Product not found")
    return product


# ---------------------------------------------------------------------------
# Endpoints
# ---------------------------------------------------------------------------

@app.get("/health")
def health() -> dict:
    return {"status": "ok"}


# ---------------------------------------------------------------------------
# Admin: scheduled refresh (Render free tier has no cron jobs)
# ---------------------------------------------------------------------------
# Render's free plan has no cron jobs, so an external scheduler
# (cron-job.org, free) calls POST /admin/refresh every 30 minutes.
# The refresh pass fetches 9 store pages and takes ~30-90 seconds, but
# cron-job.org times out after 30 seconds -- so this endpoint does NOT
# run the refresh inline. It starts one refresh pass in a background
# thread and returns 202 immediately; the run's counts are available
# afterwards from GET /admin/refresh/status. A second POST while a run
# is in progress gets 409 instead of starting a duplicate run.
#
# Auth: header `X-Refresh-Token: <REFRESH_TOKEN>`. The token comes
# from the REFRESH_TOKEN env var (on Render it is generated by the
# Blueprint -- see render.yaml -- and copied from the dashboard).
# It is never hardcoded and never logged. If REFRESH_TOKEN is unset,
# both endpoints return 503 (refresh disabled) instead of running
# unauthenticated.

_refresh_lock = threading.Lock()
_refresh_state: dict = {"running": False, "last_run": None}


def _require_refresh_token(
    x_refresh_token: str | None = Header(default=None),
) -> None:
    expected = os.environ.get("REFRESH_TOKEN")
    if not expected:
        raise HTTPException(
            status_code=503,
            detail="Refresh not configured (REFRESH_TOKEN unset)",
        )
    if x_refresh_token is None or not secrets.compare_digest(
        x_refresh_token, expected
    ):
        raise HTTPException(status_code=401, detail="Invalid refresh token")


def _run_refresh_in_background() -> None:
    """Run one refresh pass in a thread; record its summary for
    GET /admin/refresh/status. Runs at most one at a time (the POST
    handler holds the lock while starting)."""
    from refresh import refresh

    started_at = datetime.now(timezone.utc).isoformat()
    try:
        summary = refresh()
        _refresh_state["last_run"] = {
            "started_at": started_at,
            "finished_at": datetime.now(timezone.utc).isoformat(),
            "status": "ok",
            "summary": summary,
        }
        log.info("Admin refresh finished: %s", summary)
    except Exception as exc:  # noqa: BLE001 - record the failure, keep the API up
        _refresh_state["last_run"] = {
            "started_at": started_at,
            "finished_at": datetime.now(timezone.utc).isoformat(),
            "status": "error",
            "error": str(exc),
        }
        log.exception("Admin refresh failed: %s", exc)
    finally:
        with _refresh_lock:
            _refresh_state["running"] = False


@app.post("/admin/refresh", status_code=202)
def admin_refresh(_: None = Depends(_require_refresh_token)) -> dict:
    with _refresh_lock:
        if _refresh_state["running"]:
            raise HTTPException(
                status_code=409, detail="A refresh is already running"
            )
        _refresh_state["running"] = True
    thread = threading.Thread(
        target=_run_refresh_in_background, daemon=True, name="pryzo-refresh"
    )
    thread.start()
    return {"status": "started"}


@app.get("/admin/refresh/status")
def admin_refresh_status(_: None = Depends(_require_refresh_token)) -> dict:
    return {
        "running": _refresh_state["running"],
        "last_run": _refresh_state["last_run"],
    }


@app.get("/search")
def search(q: str = Query(default=""), db: Session = Depends(get_db)) -> list[dict]:
    """Search products by name/brand (case-insensitive). Empty q returns all."""
    query = db.query(Product)
    if q:
        like = f"%{q}%"
        query = query.filter(
            (Product.name.ilike(like)) | (Product.brand.ilike(like))
        )
    products = query.order_by(Product.name.asc()).all()
    return [_product_summary(db, p) for p in products]


@app.get("/products/{product_id}")
def get_product(product_id: int, db: Session = Depends(get_db)) -> dict:
    product = _get_product_or_404(db, product_id)
    detail = _product_summary(db, product)
    detail["product_urls"] = product.product_urls
    return detail


@app.get("/products/{product_id}/compare")
def compare(product_id: int, db: Session = Depends(get_db)) -> dict:
    product = _get_product_or_404(db, product_id)
    latest = _latest_prices(db, product_id)
    prices = [_price_row(db, rec) for rec in latest]
    cheapest = prices[0] if prices else None
    savings = 0.0
    if len(prices) >= 2:
        savings = round(max(p["price"] for p in prices) - min(p["price"] for p in prices), 2)
    return {
        "product": _product_summary(db, product),
        "prices": prices,
        "cheapest": cheapest,
        "savings_vs_max": savings,
    }


@app.get("/products/{product_id}/advice")
def advice(product_id: int, db: Session = Depends(get_db)) -> dict:
    """Buy-now-or-wait advice from LIVE price history (last 30 days).

    Verdicts: 'buy_now' (current <= 30d low x 1.02), 'wait' (current
    >= 30d average x 1.05), 'fair' (in between), 'unknown' (fewer
    than 3 live points in 30 days -- never a verdict from sample
    data, and never from too little data). Sample points are excluded
    entirely: they cannot move the verdict, the low, or the average.
    """
    _get_product_or_404(db, product_id)
    since = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=30)
    points = (
        db.query(PriceRecord.price)
        .filter(
            PriceRecord.product_id == product_id,
            PriceRecord.is_sample.is_(False),
            PriceRecord.fetched_at >= since,
        )
        .all()
    )
    values = [p[0] for p in points]
    latest = _latest_prices(db, product_id)
    current = min((r.price for r in latest), default=None)
    if not values:
        return {
            "product_id": product_id,
            "current": float(current) if current is not None else None,
            "low_30d": None,
            "avg_30d": None,
            "points_used": 0,
            "verdict": "unknown",
        }
    low_30d = min(values)
    avg_30d = sum(values) / len(values)
    if len(values) < 3:
        verdict = "unknown"
    elif current is not None and current <= low_30d * 1.02:
        verdict = "buy_now"
    elif current is not None and current >= avg_30d * 1.05:
        verdict = "wait"
    else:
        verdict = "fair"
    return {
        "product_id": product_id,
        "current": float(current) if current is not None else None,
        "low_30d": float(low_30d),
        "avg_30d": round(float(avg_30d), 2),
        "points_used": len(values),
        "verdict": verdict,
    }


@app.get("/products/{product_id}/coupons")
def product_coupons(product_id: int, db: Session = Depends(get_db)) -> list[dict]:
    """Active coupons for the stores carrying this product. Sample
    coupons (is_sample=True) are labelled examples, not working codes."""
    _get_product_or_404(db, product_id)
    store_ids = [
        row[0]
        for row in db.query(PriceRecord.store_id)
        .filter(PriceRecord.product_id == product_id)
        .distinct()
        .all()
    ]
    coupons = (
        db.query(Coupon)
        .filter(Coupon.store_id.in_(store_ids), Coupon.active.is_(True))
        .order_by(Coupon.store_id.asc(), Coupon.code.asc())
        .all()
    )
    return [_coupon_row(db, c) for c in coupons]


@app.get("/coupons")
def list_coupons(
    store_slug: str | None = Query(default=None), db: Session = Depends(get_db)
) -> list[dict]:
    """Active coupons, optionally filtered to one store. Sample coupons
    (is_sample=True) are labelled examples, not working codes."""
    query = db.query(Coupon).filter(Coupon.active.is_(True))
    if store_slug:
        store = db.query(Store).filter_by(slug=store_slug).first()
        if store is None:
            raise HTTPException(status_code=404, detail="Store not found")
        query = query.filter(Coupon.store_id == store.id)
    return [_coupon_row(db, c) for c in query.order_by(Coupon.code.asc()).all()]


@app.post("/coupons", status_code=201)
def create_coupon(body: CouponCreate, db: Session = Depends(get_db)) -> dict:
    store = db.query(Store).filter_by(slug=body.store_slug).first()
    if store is None:
        raise HTTPException(status_code=404, detail="Store not found")
    if body.discount_type not in ("percent", "fixed"):
        raise HTTPException(
            status_code=400,
            detail="discount_type must be 'percent' or 'fixed'",
        )
    if body.discount_type == "percent" and body.discount_value > 100:
        raise HTTPException(
            status_code=400, detail="percent discount cannot exceed 100"
        )
    coupon = Coupon(
        store_id=store.id,
        code=body.code.strip(),
        discount_type=body.discount_type,
        discount_value=body.discount_value,
        min_order=body.min_order,
        expires_at=body.expires_at,
        is_sample=False,
        active=True,
    )
    db.add(coupon)
    db.commit()
    db.refresh(coupon)
    return _coupon_row(db, coupon)


@app.get("/products/{product_id}/history")
def history(
    product_id: int,
    days: int = Query(default=30, ge=1, le=365),
    db: Session = Depends(get_db),
) -> list[dict]:
    _get_product_or_404(db, product_id)
    since = datetime.now(timezone.utc).replace(tzinfo=None) - timedelta(days=days)
    records = (
        db.query(PriceRecord)
        .filter(
            PriceRecord.product_id == product_id,
            PriceRecord.fetched_at >= since,
        )
        .order_by(PriceRecord.fetched_at.desc())
        .all()
    )
    return [
        {
            "price": rec.price,
            "store": (db.get(Store, rec.store_id).name
                      if db.get(Store, rec.store_id) else str(rec.store_id)),
            "fetched_at": rec.fetched_at.isoformat(),
            # History keeps BOTH sample and live points, flagged, so a
            # sample price is never mistaken for a real price move.
            "is_sample": rec.is_sample,
        }
        for rec in records
    ]


@app.get("/watchlist")
def list_watchlist(db: Session = Depends(get_db)) -> list[dict]:
    items = db.query(WatchlistItem).order_by(WatchlistItem.created_at.desc()).all()
    result = []
    for item in items:
        product = db.get(Product, item.product_id)
        if product is None:
            continue
        entry = _product_summary(db, product)
        result.append({
            "id": item.id,
            "product_id": item.product_id,
            "product": entry,
            "lowest_price": entry["lowest_price"],
            "created_at": item.created_at.isoformat(),
        })
    return result


@app.post("/watchlist", status_code=201)
def add_watchlist(body: WatchlistCreate, db: Session = Depends(get_db)) -> dict:
    _get_product_or_404(db, body.product_id)
    existing = (
        db.query(WatchlistItem).filter_by(product_id=body.product_id).first()
    )
    if existing:
        raise HTTPException(status_code=409, detail="Product already in watchlist")
    item = WatchlistItem(product_id=body.product_id)
    db.add(item)
    db.commit()
    db.refresh(item)
    return {
        "id": item.id,
        "product_id": item.product_id,
        "created_at": item.created_at.isoformat(),
    }


@app.delete("/watchlist/{item_id}", status_code=204)
def remove_watchlist(item_id: int, db: Session = Depends(get_db)) -> None:
    item = db.get(WatchlistItem, item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="Watchlist item not found")
    db.delete(item)
    db.commit()
    return None


@app.post("/alerts", status_code=201)
def create_alert(body: AlertCreate, db: Session = Depends(get_db)) -> dict:
    _get_product_or_404(db, body.product_id)
    if body.alert_type not in ("price", "back_in_stock"):
        raise HTTPException(
            status_code=400,
            detail="alert_type must be 'price' or 'back_in_stock'",
        )
    if body.alert_type == "price" and body.target_price is None:
        raise HTTPException(
            status_code=400,
            detail="target_price is required for price alerts",
        )
    if body.store_slug:
        store = db.query(Store).filter_by(slug=body.store_slug).first()
        if store is None:
            raise HTTPException(status_code=404, detail="Store not found")
    alert = PriceAlert(
        product_id=body.product_id,
        target_price=body.target_price,
        alert_type=body.alert_type,
        store_slug=body.store_slug,
    )
    db.add(alert)
    db.commit()
    db.refresh(alert)
    return {
        "id": alert.id,
        "product_id": alert.product_id,
        "target_price": alert.target_price,
        "alert_type": alert.alert_type,
        "store_slug": alert.store_slug,
        "active": alert.active,
        "triggered": alert.triggered,
        "created_at": alert.created_at.isoformat(),
    }


@app.get("/alerts")
def list_alerts(db: Session = Depends(get_db)) -> list[dict]:
    alerts = db.query(PriceAlert).order_by(PriceAlert.created_at.desc()).all()
    result = []
    for alert in alerts:
        product = db.get(Product, alert.product_id)
        result.append({
            "id": alert.id,
            "product_id": alert.product_id,
            "product_name": product.name if product else None,
            "target_price": alert.target_price,
            "alert_type": alert.alert_type,
            "store_slug": alert.store_slug,
            "active": alert.active,
            "triggered": alert.triggered,
            "created_at": alert.created_at.isoformat(),
        })
    return result
