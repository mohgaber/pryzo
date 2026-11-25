# SAMPLE DATA ONLY -- NOT LIVE PRICES.
# Every price seeded by this file is a plausible example in EGP, written so
# the app can be demoed before real store polling is wired up. These numbers
# were NOT fetched from any store and must never be presented to users as
# live prices. Real prices come from crawler.fetch_price() via refresh.py.
# Idempotent: safe to re-run -- stores/products are matched by slug/name and
# sample prices are only added once per product/store pair.

"""Seed Pryzo with stores and example electronics products (SAMPLE prices)."""

from datetime import datetime, timedelta, timezone

from models import (
    Coupon,
    InstallmentPlan,
    PriceRecord,
    Product,
    SessionLocal,
    Store,
    StoreShipping,
    init_db,
)

STORES = [
    ("Dream 2000", "dream2000", "https://dream2000.com"),
    ("Vodafone", "vodafone", "https://eshop.vodafone.com.eg"),
    ("Amazon Egypt", "amazon-eg", "https://www.amazon.eg"),
    ("Noon", "noon", "https://www.noon.com/egypt-en"),
    ("Jumia Egypt", "jumia-eg", "https://www.jumia.com.eg"),
    ("Carrefour", "carrefour", "https://www.carrefouregypt.com"),
    ("Souq.com", "souq", "https://egypt.souq.com"),
]

# Product URLs: verified real product-page URLs where one was confirmed
# (2026-11-25, Phase 2) by fetching the page with the crawler CLI and
# extracting THAT product's price from it. Stores without a verified
# product page keep a search URL as a "find it on the store" link only --
# refresh.py skips search URLs on purpose (a search page's first price
# is usually some other listing's price). Verified 2026-11-25:
#   Amazon EG: PS5 Slim Disc B0CWH9WCWT 50,500 / Philips HD9270
#     B08WJBVM5G 7,269 / Sony WH-1000XM5 B0BXYCS74H 11,999 /
#     AirPods Pro 2 (USB-C) B0CHWRXH8B 13,999.
#   Jumia EG: PS5 Slim Disc 50,000 / iPhone 15 128GB 50,500 /
#     Philips HD9270/90 7,899 / Sony WH-1000XM5 (Light Blue) 17,106.
#   Vodafone eShop: iPhone 15 128GB 54,999.
# NOT verified (no live URL wired, sample prices only):
#   Galaxy S24 / Galaxy A55: the 2024 models are gone from Amazon,
#     Jumia, Dream 2000 and Vodafone -- only successors (S25 FE / S26
#     FE, A56 / A57) are listed. LG 43UR78006: discontinued, only the
#     newer NU85 43" 4K model is listed. Redmi Note 13: Amazon's page
#     (B0CWRLJYGJ) is currently unavailable with no buy-box price;
#     Jumia lists no plain Note 13. AirPods Pro 2 on Jumia: only
#     generic knockoffs on page 1.
#   Noon and Carrefour Egypt: unreachable from this sandbox (all
#     requests time out, 60s+), so their pages could not be verified
#     with the crawler -- Noon product URLs found via search
#     (PS5 N70022609V, iPhone 15 N53433297A) are NOT wired in.
# Image URLs below were HEAD-checked (HTTP 200, image/jpeg) 2026-11-25.
def _jumia_search(q: str) -> str:
    return "https://www.jumia.com.eg/catalog/?q=" + q.replace(" ", "+")


def _amazon_search(q: str) -> str:
    return "https://www.amazon.eg/s?k=" + q.replace(" ", "+")


def _is_search_url(url: str) -> bool:
    """Same markers as refresh.py: search-result pages, not product pages."""
    return any(m in url for m in ("/catalog/?q=", "/catalog/?", "/s?k=", "/s?"))


# (name, brand, category, image_url, {store_slug: sample_price_EGP},
#  {store_slug: product_url})
PRODUCTS = [
    (
        "PlayStation 5 Console (Disc Edition)",
        "Sony",
        "Gaming",
        "https://m.media-amazon.com/images/I/51dR+MAtBjL._AC_SL1500_.jpg",
        {"jumia-eg": 32999.0, "amazon-eg": 34999.0, "noon": 33999.0},
        {"jumia-eg": "https://www.jumia.com.eg/sony-playstation-5-slim-console-disc-1-tb-storage-capacity-white-1-year-warranty-135064899.html",
         "amazon-eg": "https://www.amazon.eg/dp/B0CWH9WCWT"},
    ),
    (
        "iPhone 15 128GB",
        "Apple",
        "Smartphones",
        "https://eg.jumia.is/unsafe/fit-in/680x680/filters:fill(white)/product/55/6164531/1.jpg?5891",
        {"amazon-eg": 45999.0, "jumia-eg": 46999.0, "noon": 44999.0},
        {"jumia-eg": "https://www.jumia.com.eg/apple-iphone-15-single-sim-5g-128gb-black-135461655.html",
         "vodafone": "https://eshop.vodafone.com.eg/en/prod/iphone-15",
         "amazon-eg": _amazon_search("iPhone 15 128GB")},
    ),
    (
        "Samsung Galaxy S24 256GB",
        "Samsung",
        "Smartphones",
        None,
        {"jumia-eg": 38999.0, "amazon-eg": 39999.0},
        {"jumia-eg": _jumia_search("Samsung Galaxy S24"),
         "amazon-eg": _amazon_search("Samsung Galaxy S24")},
    ),
    (
        "Samsung Galaxy A55 5G 256GB",
        "Samsung",
        "Smartphones",
        None,
        {"jumia-eg": 18999.0, "amazon-eg": 19499.0, "noon": 18499.0},
        {"jumia-eg": _jumia_search("Samsung Galaxy A55"),
         "amazon-eg": _amazon_search("Samsung Galaxy A55")},
    ),
    (
        "Philips Air Fryer XL HD9270",
        "Philips",
        "Home Appliances",
        "https://m.media-amazon.com/images/I/51iTYStwAPL._AC_SL1500_.jpg",
        {"amazon-eg": 8999.0, "jumia-eg": 9499.0, "carrefour": 8799.0},
        {"jumia-eg": "https://www.jumia.com.eg/philips-essential-air-fryer-6.2l-capacity-digital-screen-black-hd927090-130811691.html",
         "amazon-eg": "https://www.amazon.eg/dp/B08WJBVM5G"},
    ),
    (
        'LG 43" 4K UHD Smart TV 43UR78006',
        "LG",
        "TVs",
        None,
        {"jumia-eg": 15999.0, "amazon-eg": 16499.0},
        {"jumia-eg": _jumia_search('LG 43 inch 4K TV'),
         "amazon-eg": _amazon_search('LG 43 inch 4K TV')},
    ),
    (
        "Xiaomi Redmi Note 13 256GB",
        "Xiaomi",
        "Smartphones",
        None,
        {"jumia-eg": 9999.0, "amazon-eg": 10499.0, "noon": 9799.0},
        {"jumia-eg": _jumia_search("Xiaomi Redmi Note 13"),
         "amazon-eg": _amazon_search("Xiaomi Redmi Note 13")},
    ),
    (
        "Sony WH-1000XM5 Wireless Headphones",
        "Sony",
        "Audio",
        "https://m.media-amazon.com/images/I/61oUbsHuWuL._AC_SL1500_.jpg",
        {"amazon-eg": 16999.0, "jumia-eg": 17499.0},
        {"jumia-eg": "https://www.jumia.com.eg/sony-wh-1000xm5-noise-cancelling-wireless-headphones-light-blue-134480053.html",
         "amazon-eg": "https://www.amazon.eg/dp/B0BXYCS74H"},
    ),
    (
        "Apple AirPods Pro (2nd generation)",
        "Apple",
        "Audio",
        "https://m.media-amazon.com/images/I/51NRGHU2NoL._AC_SL1500_.jpg",
        {"amazon-eg": 11999.0, "jumia-eg": 12499.0, "noon": 11499.0},
        {"jumia-eg": _jumia_search("Apple AirPods Pro 2nd generation"),
         "amazon-eg": "https://www.amazon.eg/dp/B0CHWRXH8B"},
    ),
]


# Phase 3 SAMPLE estimates (2026-11-25). None of these were fetched
# from a store -- they are clearly-labelled examples (is_sample=True)
# so the app can demo installments / shipping / coupons before live
# data exists for a store. A live refresh replaces them: live
# installment plans are preferred by the compare endpoint, and a live
# shipping row replaces the sample row wholesale.
#
# Shipping estimates are rough per-store guesses (fee in EGP, free
# delivery above that order value, delivery window in days).
# (store_slug: fee, free_above, days_min, days_max)
SAMPLE_SHIPPING = {
    "amazon-eg": (0.0, 0.0, 1, 2),
    "jumia-eg": (40.0, 500.0, 3, 5),
    "vodafone": (50.0, 1000.0, 2, 4),
    "noon": (30.0, 500.0, 2, 4),
    "carrefour": (25.0, 750.0, 1, 3),
    "dream2000": (35.0, 1000.0, 2, 5),
    "souq": (30.0, 500.0, 3, 5),
}


def _seed_phase3_samples(db, stores, now) -> None:
    """Idempotent Phase 3 SAMPLE seeding (called from seed()).

    - Installment plans: 12- and 24-month SAMPLE plans for every
      product/store pair that has a SAMPLE price, monthly =
      round(price / months, 2). Skipped when the pair already has ANY
      plan (live or sample), so a re-run never duplicates or overwrites
      a live plan.
    - Shipping: one SAMPLE estimate row per store (see
      SAMPLE_SHIPPING). Skipped when the store already has a shipping
      row, so a live row is never overwritten by a sample.
    - Coupons: one SAMPLE coupon per store, code 'SAMPLE10', 10% off.
      These are NOT working codes -- the seeded flag says so, and the
      API exposes is_sample so the app can label them. Skipped when a
      coupon with the same store+code already exists.
    """
    # Installments from the SAMPLE prices seeded above.
    pairs = (
        db.query(PriceRecord.product_id, PriceRecord.store_id, PriceRecord.price)
        .filter(PriceRecord.is_sample.is_(True))
        .all()
    )
    plans_added = 0
    for product_id, store_id, price in pairs:
        exists = (
            db.query(InstallmentPlan)
            .filter_by(product_id=product_id, store_id=store_id)
            .first()
        )
        if exists:
            continue
        for months in (12, 24):
            db.add(InstallmentPlan(
                product_id=product_id,
                store_id=store_id,
                months=months,
                monthly_amount=round(price / months, 2),
                total_amount=round(round(price / months, 2) * months, 2),
                is_sample=True,
                fetched_at=now,
            ))
            plans_added += 1
    if plans_added:
        print(f"SAMPLE installment plans added: {plans_added}")

    # Shipping estimates, one row per store.
    shipping_added = 0
    for slug, (fee, free_above, d_min, d_max) in SAMPLE_SHIPPING.items():
        store = stores.get(slug)
        if store is None:
            continue
        exists = (
            db.query(StoreShipping).filter_by(store_id=store.id).first()
        )
        if exists:
            continue
        db.add(StoreShipping(
            store_id=store.id,
            fee=fee,
            free_above=free_above,
            delivery_days_min=d_min,
            delivery_days_max=d_max,
            is_sample=True,
            updated_at=now,
        ))
        shipping_added += 1
    if shipping_added:
        print(f"SAMPLE shipping rows added: {shipping_added}")

    # SAMPLE coupons (NOT working codes).
    coupons_added = 0
    for slug, store in stores.items():
        exists = (
            db.query(Coupon)
            .filter_by(store_id=store.id, code="SAMPLE10")
            .first()
        )
        if exists:
            continue
        db.add(Coupon(
            store_id=store.id,
            code="SAMPLE10",
            discount_type="percent",
            discount_value=10.0,
            min_order=None,
            expires_at=None,
            is_sample=True,
            active=True,
        ))
        coupons_added += 1
    if coupons_added:
        print(f"SAMPLE coupons added: {coupons_added}")


def seed() -> None:
    init_db()
    db = SessionLocal()
    try:
        stores = {}
        for name, slug, base_url in STORES:
            store = db.query(Store).filter_by(slug=slug).first()
            if store is None:
                store = Store(name=name, slug=slug, base_url=base_url)
                db.add(store)
                db.flush()
                print(f"Store created: {name} ({slug})")
            stores[slug] = store

        now = datetime.now(timezone.utc).replace(tzinfo=None)
        for i, (name, brand, category, image_url, prices, urls) in enumerate(PRODUCTS):
            product = db.query(Product).filter_by(name=name).first()
            if product is None:
                product = Product(
                    name=name, brand=brand, category=category,
                    image_url=image_url, product_urls=urls,
                )
                db.add(product)
                db.flush()
                print(f"Product created: {name}")
            else:
                # Verified product-page URLs OVERWRITE anything stored
                # (including an old search URL for that store). Search
                # URLs only fill keys that are missing, so a re-run can
                # never downgrade a verified URL back to a search URL.
                merged = dict(product.product_urls or {})
                for slug, url in urls.items():
                    if not _is_search_url(url) or slug not in merged:
                        merged[slug] = url
                product.product_urls = merged
                if image_url and not product.image_url:
                    product.image_url = image_url

            # Add each SAMPLE price once (skip if this product/store already
            # has any price record, so re-runs never duplicate history).
            # Existing rows are never touched: a re-run can therefore
            # never flip a LIVE row to sample (or change any live price).
            for slug, price in prices.items():
                store = stores[slug]
                exists = (
                    db.query(PriceRecord)
                    .filter_by(product_id=product.id, store_id=store.id)
                    .first()
                )
                if exists:
                    continue
                db.add(PriceRecord(
                    product_id=product.id,
                    store_id=store.id,
                    price=price,
                    currency="EGP",
                    in_stock=True,
                    url=urls.get(slug),
                    is_sample=True,
                    # Stagger slightly so history ordering is deterministic.
                    fetched_at=now - timedelta(minutes=i),
                ))
        _seed_phase3_samples(db, stores, now)
        db.commit()
        print(
            f"Seed done: {db.query(Store).count()} stores, "
            f"{db.query(Product).count()} products, "
            f"{db.query(PriceRecord).count()} price records (SAMPLE prices)."
        )
    finally:
        db.close()


if __name__ == "__main__":
    seed()
