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
    # Added 2026-11-26 ("do like PriceTeq"): the big Egyptian shops
    # PriceTeq tracks, crawled directly (never PriceTeq's own data —
    # its ToS forbids bulk scraping). Verified product pages exist.
    ("Sharaf DG", "sharafdg", "https://egypt.sharafdg.com"),
    ("2B", "2b", "https://2b.com.eg"),
    ("B.TECH", "btech", "https://btech.com"),
    ("Raya Shop", "rayashop", "https://www.rayashop.com"),
    ("Ehab Group", "ehabgroup", "https://www.ehabgroup.com"),
    ("wazen", "wazen", "https://wazen.eg"),
    ("iMedia", "imedia", "https://www.imediastores.com"),
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
# 2026-11-26 ("do like PriceTeq"): 7 new shops added (Sharaf DG, 2B,
# B.TECH, Raya Shop, Ehab Group, wazen, iMedia) and the 4 products
# dropped earlier the same day (S24, A55, LG 43UR78006, Redmi Note 13)
# are BACK — the new shops carry them with real (mostly out-of-stock)
# prices. PriceTeq's own data is NEVER used: its ToS forbids bulk
# scraping ("Do not scrape or copy the site in bulk"). We crawl the
# shops directly, like PriceTeq does; its public shop list was only
# the directory of which shops exist.
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
        {"jumia-eg": 32999.0, "amazon-eg": 34999.0, "noon": 33999.0,
         "sharafdg": 43399.0, "2b": 38359.0},
        {"jumia-eg": "https://www.jumia.com.eg/sony-playstation-5-slim-console-disc-1-tb-storage-capacity-white-1-year-warranty-135064899.html",
         "amazon-eg": "https://www.amazon.eg/dp/B0CWH9WCWT",
         # Verified 2026-11-26: Sharaf DG 43,399 EGP (in stock, price
         # from a 127-day-old page copy — the refresh re-fetches live);
         # 2B 38,359 EGP, out of stock.
         "sharafdg": "https://egypt.sharafdg.com/product/sony-playstation-5-slim-console-2023-cd-version-white/",
         "2b": "https://2b.com.eg/en/sony-playstation-5-disc-console-slim-with-1-controller-1-year-warranty.html"},
    ),
    (
        "iPhone 15 128GB",
        "Apple",
        "Smartphones",
        "https://eg.jumia.is/unsafe/fit-in/680x680/filters:fill(white)/product/55/6164531/1.jpg?5891",
        {"amazon-eg": 45999.0, "jumia-eg": 46999.0, "noon": 44999.0,
         "sharafdg": 61999.0, "2b": 65699.0},
        {"jumia-eg": "https://www.jumia.com.eg/apple-iphone-15-single-sim-5g-128gb-black-135461655.html",
         "vodafone": "https://eshop.vodafone.com.eg/en/prod/iphone-15",
         "amazon-eg": _amazon_search("iPhone 15 128GB"),
         # Verified 2026-11-26: Sharaf DG 61,999 EGP, in stock;
         # 2B 65,699 EGP, out of stock.
         "sharafdg": "https://egypt.sharafdg.com/product/apple-iphone-15-128gb-blue-with-facetime-middle-east-version/",
         "2b": "https://2b.com.eg/en/apple-iphone-15-128gb-blue-official-warranty.html"},
    ),
    (
        "Philips Air Fryer XL HD9270",
        "Philips",
        "Home Appliances",
        "https://m.media-amazon.com/images/I/51iTYStwAPL._AC_SL1500_.jpg",
        {"amazon-eg": 8999.0, "jumia-eg": 9499.0, "carrefour": 8799.0,
         "btech": 7987.0, "rayashop": 7715.0},
        {"jumia-eg": "https://www.jumia.com.eg/philips-essential-air-fryer-6.2l-capacity-digital-screen-black-hd927090-130811691.html",
         "amazon-eg": "https://www.amazon.eg/dp/B08WJBVM5G",
         # Verified 2026-11-26, both in stock: B.TECH 7,987 EGP,
         # Raya Shop 7,715 EGP (HD9270/90).
         "btech": "https://btech.com/en/p/philips-air-fryer-hd9270-90-1635765899?offering_id=58f379a6-3576-4ce5-b1ad-e74c79b741cf",
         "rayashop": "https://www.rayashop.com/en/philips-essential-xl-digital-air-fryer-62-liter-2000-watt-black-hd927090-international-warranty-1-b0f52141"},
    ),
    (
        "Sony WH-1000XM5 Wireless Headphones",
        "Sony",
        "Audio",
        "https://m.media-amazon.com/images/I/61oUbsHuWuL._AC_SL1500_.jpg",
        {"amazon-eg": 16999.0, "jumia-eg": 17499.0, "btech": 14999.0},
        {"jumia-eg": "https://www.jumia.com.eg/sony-wh-1000xm5-noise-cancelling-wireless-headphones-light-blue-134480053.html",
         "amazon-eg": "https://www.amazon.eg/dp/B0BXYCS74H",
         # Verified 2026-11-26: B.TECH Black 14,999 EGP, out of stock.
         "btech": "https://btech.com/en/p/sony-wireless-headphones-microphone-black-wh-1000xm5"},
    ),
    (
        "Apple AirPods Pro (2nd generation)",
        "Apple",
        "Audio",
        "https://m.media-amazon.com/images/I/51NRGHU2NoL._AC_SL1500_.jpg",
        {"amazon-eg": 11999.0, "jumia-eg": 12499.0, "noon": 11499.0,
         "ehabgroup": 10070.0},
        {"jumia-eg": _jumia_search("Apple AirPods Pro 2nd generation"),
         "amazon-eg": "https://www.amazon.eg/dp/B0CHWRXH8B",
         # Verified 2026-11-26 via Vodafone eShop on-site search (live
         # browser): exact model, genuine Apple, price 10,999 EGP.
         # Page says out of stock, so the refresh records it as
         # unavailable — still a real live price, not a sample.
         "vodafone": "https://eshop.vodafone.com.eg/en/prod/airpods-pro-2nd-gen-with-magsafe-charging-case---type-c",
         # Verified 2026-11-26: Ehab Group 10,070 EGP, out of stock.
         # NOTE: Ehab returned HTTP 403 to the crawler from this
         # sandbox — the Railway refresh may still fail on it.
         "ehabgroup": "https://www.ehabgroup.com/shop/apple-airpods-pro-2-type-c/"},
    ),
    # Re-added 2026-11-26 ("do like PriceTeq"): these 4 were dropped
    # the same day for having no live price on the original 7 stores,
    # but the new shops DO carry them — so they are back, with live
    # prices from the new shops (mostly out of stock, recorded as such).
    (
        "Samsung Galaxy S24 256GB",
        "Samsung",
        "Smartphones",
        None,
        {"sharafdg": 46783.0, "btech": 38999.0},
        # Verified 2026-11-26: Sharaf DG Cobalt Violet 46,783 EGP,
        # out of stock. Sharaf DG fails from Railway, so B.TECH is the
        # working source — 38,999 EGP, out of stock (verified via
        # crawler: JSON-LD 38,999 EGP, in_stock false).
        {"sharafdg": "https://egypt.sharafdg.com/product/samsung-galaxy-s24-5g-256gb-8gb-cobalt-violet-dual-sim-smartphone-middle-east-version/",
         "btech": "https://btech.com/en/p/samsung-galaxy-s24-256gb-8gb-4g-lte-dual-sim-onys-black"},
    ),
    (
        "Samsung Galaxy A55 5G 256GB",
        "Samsung",
        "Smartphones",
        None,
        {"rayashop": 22999.0},
        # Verified 2026-11-26: Raya Shop Awesome Lilac 22,999 EGP,
        # sold out.
        {"rayashop": "https://www.rayashop.com/en/samsung-galaxy-a55-dual-sim-256-gb-8-gb-ram-5g-awesome-liliac-8806095518022-iplus"},
    ),
    (
        'LG 43" 4K UHD Smart TV 43UR78006',
        "LG",
        "TVs",
        None,
        {"wazen": 18135.0},
        # Verified 2026-11-26: wazen.eg 43UR78006LL 18,135 EGP, out of
        # stock. The crawler extracts this price via JSON-LD (tested).
        {"wazen": "https://wazen.eg/product/lg-tv-43-inches-4k-led-smart-43ur78006ll/"},
    ),
    # NOTE: Redmi Note 13 was NOT re-added — its only verified source
    # (iMedia) now returns HTTP 404 (the page was delisted; the
    # research copy was 304 days old), and its Amazon page is blocked
    # for the crawler. It stays dropped until a working source is found.
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
