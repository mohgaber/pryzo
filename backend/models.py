"""SQLAlchemy models for Pryzo (price-comparison backend).

Database: SQLite locally (``sqlite:///./pryzo.db`` in this directory).
Set the ``DATABASE_URL`` env var to point at PostgreSQL later, e.g.::

    DATABASE_URL=postgresql://user:password@localhost:5432/pryzo

All models are plain SQLAlchemy 2.0 and work unchanged on PostgreSQL.
"""

import os
from datetime import datetime, timezone


def _utcnow() -> datetime:
    """Naive UTC now (kept naive so SQLite/Postgres comparisons stay simple)."""
    return datetime.now(timezone.utc).replace(tzinfo=None)
from pathlib import Path

from sqlalchemy import (
    JSON,
    Boolean,
    DateTime,
    Float,
    ForeignKey,
    Integer,
    String,
    UniqueConstraint,
    create_engine,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column, relationship, sessionmaker

BASE_DIR = Path(__file__).resolve().parent
DATABASE_URL = os.environ.get(
    "DATABASE_URL", f"sqlite:///{BASE_DIR / 'pryzo.db'}"
)
# Render and Neon hand out Postgres URLs starting with "postgres://",
# but SQLAlchemy 2.0 has no "postgres" dialect plugin -- create_engine
# raises NoSuchModuleError at import time. Normalize to "postgresql://"
# (whose driver resolves to the installed psycopg v3) before use.
if DATABASE_URL.startswith("postgres://"):
    DATABASE_URL = "postgresql://" + DATABASE_URL[len("postgres://"):]

connect_args = {"check_same_thread": False} if DATABASE_URL.startswith("sqlite") else {}
engine = create_engine(DATABASE_URL, connect_args=connect_args)
SessionLocal = sessionmaker(bind=engine, autoflush=False, autocommit=False)


class Base(DeclarativeBase):
    pass


class Store(Base):
    __tablename__ = "stores"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(100), nullable=False)
    slug: Mapped[str] = mapped_column(String(50), unique=True, nullable=False)
    base_url: Mapped[str] = mapped_column(String(255), nullable=False)

    price_records: Mapped[list["PriceRecord"]] = relationship(
        "PriceRecord", back_populates="store"
    )


class Product(Base):
    __tablename__ = "products"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    name: Mapped[str] = mapped_column(String(255), nullable=False)
    brand: Mapped[str] = mapped_column(String(100), nullable=False)
    category: Mapped[str] = mapped_column(String(100), nullable=False, default="Electronics")
    image_url: Mapped[str | None] = mapped_column(String(500), nullable=True)
    # Mapping store_slug -> product page URL on that store (nullable).
    product_urls: Mapped[dict | None] = mapped_column(JSON, nullable=True)

    price_records: Mapped[list["PriceRecord"]] = relationship(
        "PriceRecord", back_populates="product", cascade="all, delete-orphan"
    )
    alerts: Mapped[list["PriceAlert"]] = relationship(
        "PriceAlert", back_populates="product", cascade="all, delete-orphan"
    )
    watchlist_items: Mapped[list["WatchlistItem"]] = relationship(
        "WatchlistItem", back_populates="product", cascade="all, delete-orphan"
    )


class PriceRecord(Base):
    __tablename__ = "price_records"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id"), nullable=False, index=True
    )
    store_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("stores.id"), nullable=False, index=True
    )
    price: Mapped[float] = mapped_column(Float, nullable=False)
    currency: Mapped[str] = mapped_column(String(10), nullable=False, default="EGP")
    in_stock: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    url: Mapped[str | None] = mapped_column(String(1000), nullable=True)
    fetched_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=_utcnow, index=True
    )
    # True for SAMPLE prices inserted by seed.py (plausible examples,
    # never fetched from a store); False for live prices inserted by
    # refresh.py via crawler.fetch_price(). Added 2026-11-25: before
    # this flag, seed and live prices shared this table with nothing
    # distinguishing them, so a SAMPLE price could be reported as the
    # "lowest price" and could trigger a price alert (the PS5 alert,
    # target 40,000 EGP, was triggered by the 32,999 EGP SAMPLE seed
    # price while the live lowest was 50,000 EGP). All lowest-price
    # computations and alert checks use LIVE records only
    # (``is_sample == False``); history returns both, flagged.
    is_sample: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)

    product: Mapped["Product"] = relationship("Product", back_populates="price_records")
    store: Mapped["Store"] = relationship("Store", back_populates="price_records")


class PriceAlert(Base):
    __tablename__ = "price_alerts"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id"), nullable=False, index=True
    )
    # NULL for back_in_stock alerts (no price target). Was NOT NULL
    # before Phase 3; see _ensure_alert_target_nullable() -- SQLite
    # needs a table rebuild to drop the NOT NULL, PostgreSQL an
    # ALTER COLUMN ... DROP NOT NULL.
    target_price: Mapped[float | None] = mapped_column(Float, nullable=True)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)
    # Set by refresh.py when the product's current lowest price drops to
    # (or below) target_price. Sticky: once True it stays True until the
    # alert is deleted/re-created, so a later price rise does not hide
    # that the target was hit. Added 2026-11-25 (Phase 2); the existing
    # dev DB was migrated with:
    #   ALTER TABLE price_alerts ADD COLUMN triggered BOOLEAN NOT NULL DEFAULT 0;
    triggered: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=_utcnow
    )
    # Phase 3 (2026-11-25): 'price' (default -- trigger when the live
    # lowest drops to target_price) or 'back_in_stock' (trigger when a
    # store that was out of stock has the product in stock again).
    alert_type: Mapped[str] = mapped_column(String(20), nullable=False, default="price")
    # Optional: only this store's stock matters. NULL = any store.
    store_slug: Mapped[str | None] = mapped_column(String(50), nullable=True)

    product: Mapped["Product"] = relationship("Product", back_populates="alerts")


class InstallmentPlan(Base):
    """Installment offer for one product at one store (Phase 3).

    One row = one plan (``months`` x ``monthly_amount``). Live rows
    come from crawler.extract_installment() via refresh.py
    (``is_sample=False``); seed.py inserts SAMPLE plans
    (``is_sample=True``: monthly = price/months, an estimate, never a
    store offer). The compare endpoint shows the latest plan per
    product/store, live preferred, sample flagged.
    """

    __tablename__ = "installment_plans"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id"), nullable=False, index=True
    )
    store_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("stores.id"), nullable=False, index=True
    )
    months: Mapped[int] = mapped_column(Integer, nullable=False)
    monthly_amount: Mapped[float] = mapped_column(Float, nullable=False)
    total_amount: Mapped[float | None] = mapped_column(Float, nullable=True)
    is_sample: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    fetched_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=_utcnow, index=True
    )


class StoreShipping(Base):
    """Shipping / delivery estimate for one store (Phase 3).

    One row per store (``store_id`` unique). Live rows come from
    crawler.extract_shipping() via refresh.py; seed.py inserts SAMPLE
    estimates (``is_sample=True``) where no live data exists. A live
    refresh REPLACES the row wholesale (fields the live extraction
    could not find become NULL, never a leftover sample estimate
    presented as live), so a row with ``is_sample=False`` holds only
    live-extracted values.
    """

    __tablename__ = "store_shipping"
    __table_args__ = (UniqueConstraint("store_id", name="uq_shipping_store"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    store_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("stores.id"), nullable=False, unique=True, index=True
    )
    fee: Mapped[float | None] = mapped_column(Float, nullable=True)
    free_above: Mapped[float | None] = mapped_column(Float, nullable=True)
    delivery_days_min: Mapped[int | None] = mapped_column(Integer, nullable=True)
    delivery_days_max: Mapped[int | None] = mapped_column(Integer, nullable=True)
    is_sample: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=_utcnow
    )


class Coupon(Base):
    """Discount code for one store (Phase 3).

    SAMPLE coupons seeded by seed.py (``is_sample=True``, e.g. code
    ``SAMPLE10``) are clearly-labelled examples -- never present a
    sample code as a working live coupon. No live coupon source is
    wired: store pages show bank/card-specific promo codes with
    per-card terms, not general store coupons, so nothing is scraped
    as a live coupon.
    """

    __tablename__ = "coupons"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    store_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("stores.id"), nullable=False, index=True
    )
    code: Mapped[str] = mapped_column(String(100), nullable=False)
    discount_type: Mapped[str] = mapped_column(String(20), nullable=False)
    discount_value: Mapped[float] = mapped_column(Float, nullable=False)
    min_order: Mapped[float | None] = mapped_column(Float, nullable=True)
    expires_at: Mapped[datetime | None] = mapped_column(DateTime, nullable=True)
    is_sample: Mapped[bool] = mapped_column(Boolean, nullable=False, default=False)
    active: Mapped[bool] = mapped_column(Boolean, nullable=False, default=True)

    store: Mapped["Store"] = relationship("Store")


class WatchlistItem(Base):
    __tablename__ = "watchlist_items"
    __table_args__ = (UniqueConstraint("product_id", name="uq_watchlist_product"),)

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    product_id: Mapped[int] = mapped_column(
        Integer, ForeignKey("products.id"), nullable=False, unique=True, index=True
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime, nullable=False, default=_utcnow
    )

    product: Mapped["Product"] = relationship("Product", back_populates="watchlist_items")


def init_db() -> None:
    """Create all tables (safe to call repeatedly)."""
    Base.metadata.create_all(bind=engine)
    _ensure_triggered_column()
    _ensure_is_sample_column()
    _ensure_alert_type_column()
    _ensure_alert_store_slug_column()
    _ensure_alert_target_nullable()


def _ensure_triggered_column() -> None:
    """Backfill for databases created before ``PriceAlert.triggered``
    existed (added 2026-11-25, Phase 2): add the column if it is
    missing instead of crashing refresh.py / the API on a stale DB.
    A cron run at 09:00 on 2026-11-25 hit exactly this --
    ``sqlite3.OperationalError: no such column: price_alerts.triggered``
    -- because the new code deployed before the dev DB was migrated.
    Works on SQLite and PostgreSQL. NOTE: the default must be written
    ``FALSE``, not ``0`` -- PostgreSQL rejects ``DEFAULT 0`` on a
    boolean column (``DatatypeMismatch``, found 2026-11-25 when the
    same statement was first run against Postgres); SQLite accepts
    ``FALSE`` as 0.
    """
    from sqlalchemy import inspect, text

    cols = [c["name"] for c in inspect(engine).get_columns("price_alerts")]
    if "triggered" in cols:
        return
    with engine.begin() as conn:
        conn.execute(
            text(
                "ALTER TABLE price_alerts "
                "ADD COLUMN triggered BOOLEAN NOT NULL DEFAULT FALSE"
            )
        )


def _ensure_is_sample_column() -> None:
    """Backfill for databases created before ``PriceRecord.is_sample``
    existed (added 2026-11-25): add the column if it is missing instead
    of crashing refresh.py / the API on a stale DB. Mirrors
    ``_ensure_triggered_column`` above.

    NOTE: this only adds the column (default False). It deliberately
    does NOT guess which pre-existing rows were samples: seed rows and
    live rows are indistinguishable in a pre-flag DB (the earliest
    record per product/store is usually the seed row, but not always
    -- e.g. iPhone 15 @ Vodafone has only a live row, no seed row --
    so no per-pair rule classifies them correctly). Existing DBs must
    be classified by the one-off migration documented in README.md
    ("Migration note -- ``price_records.is_sample``"), which for the
    dev DB marks every row fetched before the first flagged refresh
    run as sample. A stale DB that only ever gains the column through
    this function keeps its old rows as ``is_sample=False`` until that
    migration is run -- run it, do not rely on this default.
    Works on SQLite and PostgreSQL: the default is written ``FALSE``
    (``DEFAULT 0`` is rejected by PostgreSQL on a boolean column).
    """
    from sqlalchemy import inspect, text

    cols = [c["name"] for c in inspect(engine).get_columns("price_records")]
    if "is_sample" in cols:
        return
    with engine.begin() as conn:
        conn.execute(
            text(
                "ALTER TABLE price_records "
                "ADD COLUMN is_sample BOOLEAN NOT NULL DEFAULT FALSE"
            )
        )


def _ensure_column(table: str, column: str, ddl: str) -> None:
    """Generic self-healing backfill: add ``column`` to ``table`` with
    ``ddl`` (e.g. ``"VARCHAR(20) NOT NULL DEFAULT 'price'"``) if it is
    missing. Works on SQLite and PostgreSQL; boolean defaults must be
    written ``FALSE``, never ``0`` (PostgreSQL rejects ``DEFAULT 0``
    on a boolean column)."""
    from sqlalchemy import inspect, text

    cols = [c["name"] for c in inspect(engine).get_columns(table)]
    if column in cols:
        return
    with engine.begin() as conn:
        conn.execute(text(f"ALTER TABLE {table} ADD COLUMN {column} {ddl}"))


def _ensure_alert_type_column() -> None:
    """Backfill for DBs created before Phase 3 (2026-11-25):
    ``PriceAlert.alert_type`` ('price' | 'back_in_stock')."""
    _ensure_column(
        "price_alerts", "alert_type", "VARCHAR(20) NOT NULL DEFAULT 'price'"
    )


def _ensure_alert_store_slug_column() -> None:
    """Backfill for DBs created before Phase 3 (2026-11-25):
    ``PriceAlert.store_slug`` (NULL = any store)."""
    _ensure_column("price_alerts", "store_slug", "VARCHAR(50) NULL")


def _ensure_alert_target_nullable() -> None:
    """Backfill for DBs created before Phase 3 (2026-11-25):
    ``PriceAlert.target_price`` must become NULLABLE -- back_in_stock
    alerts have no price target. PostgreSQL: one ALTER COLUMN.
    SQLite has no ALTER COLUMN, so the table is rebuilt (new table,
    copy rows, drop, rename) -- data is preserved; the dev DB backup
    is /tmp/pryzo.db.bak-2026-11-25-phase3. No-op when the column is
    already nullable or the table was freshly created by create_all
    (which already declares it nullable)."""
    from sqlalchemy import inspect, text

    cols = {c["name"]: c for c in inspect(engine).get_columns("price_alerts")}
    col = cols.get("target_price")
    if col is None or col.get("nullable", True):
        return
    if engine.dialect.name == "postgresql":
        with engine.begin() as conn:
            conn.execute(
                text(
                    "ALTER TABLE price_alerts "
                    "ALTER COLUMN target_price DROP NOT NULL"
                )
            )
        return
    # SQLite: rebuild the table with target_price nullable.
    with engine.begin() as conn:
        conn.execute(text("PRAGMA foreign_keys=OFF"))
        conn.execute(
            text(
                "CREATE TABLE price_alerts_new ("
                "id INTEGER NOT NULL PRIMARY KEY, "
                "product_id INTEGER NOT NULL, "
                "target_price FLOAT, "
                "active BOOLEAN NOT NULL, "
                "triggered BOOLEAN NOT NULL, "
                "created_at DATETIME NOT NULL, "
                "alert_type VARCHAR(20) NOT NULL DEFAULT 'price', "
                "store_slug VARCHAR(50), "
                "FOREIGN KEY(product_id) REFERENCES products (id))"
            )
        )
        conn.execute(
            text(
                "INSERT INTO price_alerts_new "
                "(id, product_id, target_price, active, triggered, "
                "created_at, alert_type, store_slug) "
                "SELECT id, product_id, target_price, active, triggered, "
                "created_at, alert_type, store_slug FROM price_alerts"
            )
        )
        conn.execute(text("DROP TABLE price_alerts"))
        conn.execute(
            text("ALTER TABLE price_alerts_new RENAME TO price_alerts")
        )
        conn.execute(
            text(
                "CREATE INDEX IF NOT EXISTS ix_price_alerts_product_id "
                "ON price_alerts (product_id)"
            )
        )
        conn.execute(text("PRAGMA foreign_keys=ON"))


def get_db():
    """FastAPI dependency: yields a session, closes it afterwards."""
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
