# Pryzo — Price Comparison App (Phase 1)

Pryzo compares product prices across Egyptian online stores (Dream 2000,
Vodafone online shop, Amazon Egypt, Noon, Jumia Egypt, Carrefour, Souq.com)
so a buyer picks the cheapest place. Arabic RTL UI. Prices are kept fresh by
a backend that re-checks store pages on a schedule (every 30 minutes in the
plan) — no store pushes prices to us, we poll them.

**Status: Phase 1 complete, Phase 2 backend complete (2026-11-25), Phase 3
backend complete (2026-11-25).**
Working backend API + working Flutter app with sample data. Live
prices now flow for 5 of 9 products (9 verified product-page URLs,
9 live price records in the DB). No APK yet (Phase 2, app track).

## Layout

```
pryzo/
├── backend/   FastAPI + SQLAlchemy (SQLite locally, PostgreSQL-ready)
├── app/       Flutter app (Arabic RTL, Pryzo branding)
└── README.md  this file
```

## Backend — `backend/`

Stack: Python 3, FastAPI, SQLAlchemy, requests + BeautifulSoup crawler.

```bash
cd backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python seed.py            # creates 7 stores, 9 products, 24 SAMPLE prices
uvicorn main:app --reload --port 8000
```

API (all JSON, prices in EGP, `fetched_at` is ISO-8601 UTC):

| Method | Endpoint | Description |
|---|---|---|
| GET | /health | `{"status": "ok"}` |
| GET | /search?q=... | Search products (empty `q` = all) |
| GET | /products/{id} | Product detail |
| GET | /products/{id}/compare | Store LIVE prices, cheapest first + savings (samples excluded) |
| GET | /products/{id}/history?days=30 | Price points, newest first (sample + live, each flagged `is_sample`) |
| GET | /watchlist | Watchlist with product + lowest price |
| POST | /watchlist `{"product_id": n}` | Add (201; duplicate → 409) |
| DELETE | /watchlist/{id} | Remove (204) |
| POST | /alerts `{"product_id": n, "target_price": x}` | Create alert (201) |
| GET | /alerts | List alerts (each has `triggered`, set by the refresh job when the product's current lowest price hits the target) |
| GET | /products/{id}/compare | *(Phase 3)* each price row also carries installments (`installment_monthly`, `installment_months`, `installment_is_sample`), shipping (`shipping_fee`, `shipping_is_sample`, `delivery_days_min/max`) and `total_price` (price + fee when known) |
| GET | /products/{id}/advice | *(Phase 3)* buy-now-or-wait from LIVE 30-day history: `{current, low_30d, avg_30d, points_used, verdict}` (`buy_now` / `wait` / `fair` / `unknown`) |
| GET | /products/{id}/coupons | *(Phase 3)* active coupons for the stores carrying the product |
| GET | /coupons?store_slug=... | *(Phase 3)* active coupons, optionally per store |
| POST | /coupons | *(Phase 3)* create a coupon (201) |
| POST | /alerts (extended) | *(Phase 3)* `{"product_id", "target_price"?, "alert_type": "price"\|"back_in_stock", "store_slug"?}` — back-in-stock alerts fire when a store goes from out-of-stock to in-stock |

Database: SQLite `pryzo.db` by default; set `DATABASE_URL` to switch to
PostgreSQL — verified end-to-end 2026-11-25 against a local
PostgreSQL 16 instance (seed + queries + API served from Postgres).
Interactive docs at http://127.0.0.1:8000/docs.

### Crawler

```bash
python crawler.py amazon-eg "https://www.amazon.eg/dp/B0CWH9WCWT"
python refresh.py          # one refresh pass over all products with URLs
```

The crawler sends the identifying bot User-Agent `PryzoBot/1.0`
(switched 2026-11-25 from a desktop UA — Jumia blocked the desktop
UA with HTTP 403 and its robots.txt asks bots to identify
themselves), respects robots.txt, waits ≥2s between requests, and
extracts price via JSON-LD `offers.price` first, then meta tags /
Amazon buy-box spans / selectors. It never fakes a price — on a block
it returns `None` with a logged reason. Phase 2 also fixed two real
crawler bugs: robots.txt failing *closed* when unreachable (empty
parser answers `can_fetch() == False`), and Amazon's offscreen price
text dropping the decimal point (`EGP11,99900` → 1,199,900 EGP) plus
recommendation prices being read as the product's price on
unavailable pages.

**Live-test findings (25 Nov 2026, verified with the crawler CLI on
real product pages):**
- **Amazon Egypt works** — PS5 Slim Disc 50,500 · Philips HD9270
  7,269 · Sony WH-1000XM5 11,999 · AirPods Pro 2 (USB-C) 13,999 EGP.
- **Jumia Egypt works now** (was 403-blocked under the desktop UA)
  — PS5 Slim Disc 50,000 · iPhone 15 128GB 50,500 · Philips
  HD9270/90 7,899 · Sony WH-1000XM5 17,106 EGP.
- **Vodafone eShop works** — iPhone 15 128GB 54,999 EGP.
- **Noon and Carrefour Egypt are unreachable from this sandbox**
  (all requests time out, 60s+) — their URLs are *not* wired in.
- **Dream 2000 is reachable but lists none of the 9 exact models.**
- **No live URL for Galaxy S24, Galaxy A55, LG 43UR78006, Redmi
  Note 13:** S24/A55/LG are discontinued (stores list only
  successors — S25/S26 FE, A56/A57, LG NU85); Redmi Note 13's Amazon
  page is currently unavailable with no buy-box price. Their prices
  stay SAMPLE-only.
- **Search URLs must not be refreshed** — `refresh.py` skips them: an
  Amazon search page returns the *first* price on the page, not the
  product's price ("iPhone 15" → 427.50 EGP accessories). Live
  refreshing only works on verified product-page URLs (9 wired in
  `backend/seed.py`; 5 products live, 9 live records after the
  2026-11-25 09:04 UTC refresh run: checked=9 updated=9 failed=0).

### Refresh schedule

Installed as a real cron job in this environment (cron daemon
running, verified by observed runs 2026-11-25):

```cron
*/30 * * * * cd /home/hatch/workspace/pryzo/backend && /home/hatch/workspace/pryzo/backend/.venv/bin/python refresh.py >> /home/hatch/workspace/pryzo/backend/refresh.log 2>&1
```

Runs append to `backend/refresh.log`. Each run also marks price
alerts `triggered` when the product's current lowest price reaches
the target (exposed in `GET /alerts`).

### Phase 3 (backend, 2026-11-25) — installments, shipping, coupons, back-in-stock alerts, buy-now-or-wait

- **Installments (LIVE):** Amazon Egypt (12-month 0% plan on all 4 live
  products — PS5 4,208.33, Philips 605.75, XM5 999.92, AirPods 1,166.58
  EGP/mo) and Vodafone eShop (iPhone 15: 12 × 4,583 EGP/mo). Jumia
  shows a term but no monthly amount, so no live plan is stored there.
  SAMPLE 12/24-month plans (price/months) exist as flagged fallbacks.
- **Shipping (LIVE):** Amazon (free, 1 day); Jumia (4–5 days, free above
  500 EGP — fee NOT stored live, the page contradicts itself). Other
  stores: SAMPLE estimates only.
- **Coupons:** SAMPLE only (`SAMPLE10`, 10% off per store) — no live
  coupon source exists (store pages show card-specific promo codes, not
  general coupons). `POST /coupons` creates live ones.
- **Back-in-stock alerts:** `POST /alerts` with `alert_type:
  "back_in_stock"` (+ optional `store_slug`); refresh marks them
  triggered on an out-of-stock → in-stock transition (verified with a
  simulated transition, including store scoping).
- **Advice:** `GET /products/{id}/advice` from LIVE 30-day history
  only; PS5 currently returns `buy_now` (current 50,000 = 30-day low).
  Full per-store coverage, test commands and the smoke-test evidence
  are in `backend/README.md` ("Phase 3").

### PostgreSQL

PostgreSQL 16 runs locally in this sandbox (`pryzo` database, user
`pryzo`); `DATABASE_URL=postgresql+psycopg://pryzo:pryzo_dev@localhost:5432/pryzo`
was verified end-to-end (seed + queries + API). For production,
point `DATABASE_URL` at the production instance and run `seed.py`
once. See `backend/README.md` for the migration note on the
`price_alerts.triggered` column.

## Flutter app — `app/`

```bash
cd app
flutter pub get
flutter analyze     # 0 errors (10 info-level SDK deprecation notices, see below)
flutter run         # needs a device/emulator; backend must run first for live data
```

- Package: `com.pryzo.pryzo`. Arabic RTL, slate theme (`#475569`), Pryzo
  price-tag logo in the AppBar.
- 4 screens (bottom nav): **الرئيسية** (search + categories), **المقارنة**
  (store table cheapest-first, "الأرخص" badge, savings line, watchlist +
  alert actions), **الأسعار** (CustomPainter price-history chart + alerts),
  **المتابعة** (watchlist, swipe-to-remove).
- `lib/services/api_service.dart` talks to the backend (default
  `http://127.0.0.1:8000`; Android emulator `http://10.0.2.2:8000`).
  On any network error the app falls back to bundled sample data and shows
  an amber **"أسعار تجريبية"** banner — sample prices are never presented
  as live prices.
- `flutter test` passes (smoke test boots to home, shows sample banner
  with no backend).

**Note on `flutter analyze`:** it reports 0 errors / 0 warnings and 10
info-level notices, all the same SDK-wide deprecation
(`package:flutter/material.dart` deprecated after v3.47 in this Flutter
3.50 build, suggesting `package:material_ui`). We deliberately did not
switch imports to the unverified replacement package — the app builds and
tests pass as-is.

## What is SAMPLE vs LIVE

- All seed prices in `backend/seed.py` and `app/lib/data/sample_data.dart`
  are **SAMPLE** (plausible, clearly labelled). The app shows them only
  with the "أسعار تجريبية" banner.
- **LIVE** prices now exist in the backend DB: 9 records fetched
  2026-11-25 09:04 UTC (PS5 Amazon/Jumia, iPhone 15 Jumia/Vodafone,
  Philips Amazon/Jumia, XM5 Amazon/Jumia, AirPods Pro 2 Amazon).
  Since 2026-11-25 every price record carries an `is_sample` flag
  (`seed.py` → `true`, `refresh.py` → `false`), and the API's
  "lowest price" / compare / alert check use LIVE records only — PS5
  now correctly shows Jumia 50,000 EGP as cheapest, not the 32,999
  EGP sample. History returns both kinds, each point flagged.
  The PS5 alert falsely triggered by the sample price was corrected
  to `triggered=false`.
- Products with no live URL (Galaxy S24, Galaxy A55, LG 43UR78006,
  Redmi Note 13) are SAMPLE-only until a verified product page exists
  for them.

## Deploy to Render (free tier)

The backend is deploy-ready: `render.yaml` (repo root) declares a free
web service + free PostgreSQL, `POST /admin/refresh` lets cron-job.org
(free) trigger the 30-minute refresh, and the app's API base URL is a
single constant in `app/lib/services/api_service.dart`
(`defaultBaseUrl`) to point at the live Render URL. Full step-by-step
in `backend/DEPLOY.md`. **Nothing is deployed yet** — the remaining
steps need Mohamed's GitHub + Render + cron-job.org accounts (all
free, no card). Free-tier limits: service sleeps after 15 min idle
(keep-awake ping documented), free Postgres expires after 30 days.

## Next phase (Phase 2, not done here)

1. ~~Replace seed search URLs with verified product-page URLs (Amazon first,
   then Noon / Dream 2000 / Vodafone / Carrefour); decide the Jumia UA
   question; re-test the crawler per store.~~ — done 2026-11-25 (backend
   track): 9 verified URLs, Jumia fixed via `PryzoBot/1.0`, crawler
   bugs fixed, per-store results in `backend/README.md`.
2. ~~Put `refresh.py` on a real schedule (cron or a small hosted worker) and
   switch the DB to PostgreSQL for production.~~ — done 2026-11-25
   (backend track): real `*/30` cron installed and observed running;
   PostgreSQL 16 verified end-to-end locally. Production switch =
   point `DATABASE_URL` at the production instance.
3. APK assembly (manual `flutter assemble` + aapt2/d8/zipalign/apksigner
   route used for Kora 90 — Gradle cannot run in this sandbox).
4. Real store links from the comparison screen (currently a placeholder),
   product images, and price-alert notifications.
5. ~~Fix the SAMPLE-vs-LIVE mixing: add an `is_sample` flag (or exclude
   never-refreshed stores from "lowest price") so a sample price can
   never be shown as the cheapest or trigger an alert.~~ — done
   2026-11-25 (backend track): `PriceRecord.is_sample` added, seed
   marks samples, refresh marks live, lowest/compare/alerts are
   live-only, history returns the flag per point, PS5 alert corrected
   to `triggered=false`, SQLite + PostgreSQL migrated and verified
   (see `backend/README.md`, migration note).
