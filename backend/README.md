# Pryzo Backend

FastAPI + SQLAlchemy backend for **Pryzo**, a price-comparison app for
Egyptian online stores (Dream 2000, Vodafone, Amazon Egypt, Noon, Jumia
Egypt, Carrefour, Souq.com).

> **Seed prices are SAMPLES, not live prices.** `seed.py` inserts plausible
> example prices in EGP so the app can be demoed. They were not fetched from
> any store. Live prices are collected by `refresh.py` via `crawler.py`.

## Run

```bash
cd ~/workspace/pryzo/backend
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
python seed.py
uvicorn main:app --reload --port 8000
```

API docs: http://localhost:8000/docs

Database: SQLite by default (`pryzo.db` in this folder). For PostgreSQL,
set `DATABASE_URL`, e.g.
`DATABASE_URL=postgresql+psycopg://pryzo:pryzo_dev@localhost:5432/pryzo`
(`psycopg[binary]` is in `requirements.txt`). PostgreSQL 16 was
installed and verified in this sandbox on 2026-11-25 (see below); in
production create the database/user first, then run `seed.py` with
`DATABASE_URL` set — `init_db()` creates the tables, including the
`price_alerts.triggered` column.

## Endpoints

| Method | Path | Description |
|---|---|---|
| GET | `/health` | `{"status": "ok"}` |
| POST | `/admin/refresh` | *(Render deploy)* Start one refresh pass in the background (guarded by `X-Refresh-Token: <REFRESH_TOKEN>` env var) → 202 `{"status": "started"}`; 401 wrong token, 503 token unset, 409 a run is already in progress. Returns immediately because a full pass (~30–90s) exceeds cron-job.org's 30s timeout — counts are in `GET /admin/refresh/status`. |
| GET | `/admin/refresh/status` | *(Render deploy)* Last refresh run: `{"running": bool, "last_run": {started_at, finished_at, status, summary: {checked, updated, failed, skipped}}}` (same token guard) |
| GET | `/search?q=...` | Products matching name/brand (case-insensitive); empty `q` returns all. Each item: `id, name, brand, category, image_url, lowest_price, stores_count` |
| GET | `/products/{id}` | Product detail |
| GET | `/products/{id}/compare` | Product + per-store LIVE prices only (cheapest first), `cheapest`, `savings_vs_max`. Each price row carries `is_sample: false` |
| GET | `/products/{id}/history?days=30` | Price points, latest first: `price, store, fetched_at, is_sample` — history keeps BOTH sample and live points, flagged, so a sample is never mistaken for a real price move |
| GET | `/watchlist` | Watchlist items with product info + lowest LIVE price |
| POST | `/watchlist` | `{"product_id": int}` → 201 (409 if already watched) |
| DELETE | `/watchlist/{id}` | → 204 |
| POST | `/alerts` | `{"product_id": int, "target_price": float}` → 201 |
| GET | `/alerts` | List of alerts, each with `triggered` (bool, set by `refresh.py` when the product's current LOWEST LIVE price drops to/below `target_price`; sticky once true). Sample prices can never trigger an alert |
| GET | `/products/{id}/compare` | *(Phase 3)* each price row now also carries `installment_monthly`, `installment_months`, `installment_is_sample`, `shipping_fee`, `shipping_is_sample`, `delivery_days_min`, `delivery_days_max`, `total_price` (price + fee when the fee is known, else null) |
| GET | `/products/{id}/advice` | *(Phase 3)* buy-now-or-wait from LIVE history (last 30 days): `{product_id, current, low_30d, avg_30d, points_used, verdict}` — verdict `buy_now` / `wait` / `fair` / `unknown` |
| GET | `/products/{id}/coupons` | *(Phase 3)* active coupons for the stores carrying this product |
| GET | `/coupons?store_slug=...` | *(Phase 3)* active coupons, optionally filtered to one store |
| POST | `/coupons` | *(Phase 3)* `{"store_slug", "code", "discount_type": "percent"\|"fixed", "discount_value", "min_order"?, "expires_at"?}` → 201 |

All prices are in EGP. `lowest_price` (in `/search`, `/products/{id}`,
`/watchlist`) and the `/compare` prices are **live prices only** —
`PriceRecord.is_sample` (see below) excludes SAMPLE seed prices. A
product with no live price yet reports `lowest_price: null` and an
empty compare list, however many sample prices it has. CORS is open (`allow_origins=["*"]`) so the Flutter
app can call the API from any origin.

## Price refreshing

No store pushes prices — the backend polls their public product pages.

```bash
python refresh.py          # one pass over all products with product_urls
```

Runs on a real schedule in this environment (installed 2026-11-25,
cron daemon running, verified by two observed runs — see below):

```
*/30 * * * * cd /home/hatch/workspace/pryzo/backend && /home/hatch/workspace/pryzo/backend/.venv/bin/python refresh.py >> /home/hatch/workspace/pryzo/backend/refresh.log 2>&1
```

Logs append to `refresh.log` in this folder. Each run also checks
price alerts: an active alert whose product's current lowest **LIVE**
price (latest live record per store, then the minimum — SAMPLE
records excluded) is at or below its `target_price` is marked
`triggered = true` in the DB (sticky — a later price rise does not
un-trigger it) and exposed as `triggered` in `GET /alerts`. Records
written by `refresh.py` are always `is_sample = False`; records
written by `seed.py` are always `is_sample = True`.

Test the crawler against a single page:

```bash
python crawler.py jumia-eg "https://www.jumia.com.eg/..."
python crawler.py amazon-eg "https://www.amazon.eg/..."
```

The crawler sends the identifying bot User-Agent `PryzoBot/1.0`
(switched 2026-11-25 from a desktop-browser UA: Jumia's robots.txt
says bots must identify themselves and that "bots with fake
user-agent will be blocked", and the desktop UA got HTTP 403 on every
Jumia fetch. No contact URL/email is included in the UA — we own no
pryzo domain yet, so none is invented). It respects robots.txt, waits
at least 2 seconds between requests, and returns nothing (never a fake
price) when a store blocks the request (403 / CAPTCHA) or no price is
found.

Crawler fixes in Phase 2 (2026-11-25):
- **robots.txt fail-open bug:** when robots.txt could not be fetched,
  the code cached an *unparsed* `RobotFileParser`, whose `can_fetch()`
  returns `False` for every URL — silently blocking the whole store
  (this is what killed Noon: its robots.txt times out from this
  sandbox). Unreachable robots.txt now returns `None` (fail open,
  per RFC 9309 §2.3) instead of caching the empty parser.
- **Amazon price parsing:** Amazon's offscreen price text
  concatenates whole + fraction without the decimal point
  (`EGP11,99900`), which parsed as 1,199,900 EGP. Prices are now
  read from the structured `a-price-whole` / `a-price-fraction`
  spans inside the buy-box containers only, and `_parse_price_text`
  rejects comma-grouped numbers whose last group is not 3 digits.
  On pages with no buy box (currently unavailable) the crawler now
  returns no price instead of picking up a "Customers also viewed"
  recommendation's price.
- **Regex fallback** (first `EGP …` in page text) is skipped on
  Amazon pages for the same reason.

**Live test results (2026-11-25, from this sandbox, all verified with
the crawler CLI on the real product page):**

| Store | Result | Verified live prices (EGP) |
|---|---|---|
| Amazon Egypt | **works** (9 products checked) | PS5 Slim Disc 50,500 · Philips HD9270 7,269 · Sony WH-1000XM5 11,999 · AirPods Pro 2 (USB-C) 13,999 |
| Jumia Egypt | **works after UA switch** | PS5 Slim Disc 50,000 · iPhone 15 128GB 50,500 · Philips HD9270/90 7,899 · Sony WH-1000XM5 (Light Blue) 17,106 |
| Vodafone eShop | **works** | iPhone 15 128GB 54,999 |
| Noon | **unreachable from this sandbox** — every request times out (60s+), robots.txt included; product URLs found via search (PS5 N70022609V, iPhone 15 N53433297A) are *not* wired in because they could not be verified |
| Carrefour Egypt | **unreachable from this sandbox** — same timeout behaviour as Noon |
| Dream 2000 | reachable, robots allow crawling — but none of the 9 seed products is listed as the exact model (only successors: S25/S26, A56/A57, Redmi 17, LG NU85) |

Per-product coverage after the 2026-11-25 seed update (9 verified
product-page URLs, 5 products live; `refresh.py` 2026-11-25 09:04 UTC:
checked=9 updated=9 failed=0 skipped=10 search URLs):
- PS5 Disc: Amazon + Jumia live. iPhone 15 128GB: Jumia + Vodafone
  live (no Amazon listing found). Philips HD9270: Amazon + Jumia
  live. Sony WH-1000XM5: Amazon + Jumia live. AirPods Pro 2: Amazon
  live (Jumia shows only generic knockoffs).
- **No live URL:** Galaxy S24 256GB, Galaxy A55 5G 256GB, LG 43"
  4K UR78006, Xiaomi Redmi Note 13 256GB. The first three are
  discontinued models — every store checked lists only their
  successors (S25 FE / S26 FE, A56 / A57, LG NU85 43" 4K). Redmi
  Note 13's Amazon page (B0CWRLJYGJ) is currently unavailable with
  no buy-box price, and Jumia lists no plain Note 13. Their seed
  prices stay SAMPLE-only and their search URLs are skipped by
  refresh. Do not wire a successor model's URL to these products —
  that would attach a different model's price to them.

**Cron verification (2026-11-25):** cron + PostgreSQL 16 were
installed via apt in this sandbox; the cron daemon is running and
the `*/30` job is installed (`crontab -l` shows it). Two scheduled
runs were observed in `refresh.log`: 09:00 UTC (ran before the dev
DB migration, crashed in the alert check with `no such column:
price_alerts.triggered` — that failure is what motivated the
self-healing `init_db()` below) and 09:08 UTC (ran end-to-end,
`checked=9 updated=0 failed=9 skipped=10`, all 9 fetches timing
out during a transient egress-proxy bad spell 09:08–09:13; the
network recovered minutes later and the same URLs fetch fine).
The manual run at 09:04 UTC is the clean proof: `checked=9
updated=9 failed=0`, 9 live `PriceRecord`s with `fetched_at`
2026-11-25 09:04:53 UTC in `pryzo.db` (33 records total: 24 SAMPLE
+ 9 live).

**SAMPLE vs LIVE — FIXED 2026-11-25 (`is_sample` flag):** seed prices
and live prices used to share `price_records` with no flag
distinguishing them, so "lowest price" could be a SAMPLE price — the
PS5 compare showed Noon 33,999 EGP (SAMPLE, seeded 08:03) as cheapest,
ahead of live Jumia 50,000 / Amazon 50,500, and the pre-existing PS5
alert (target 40,000 EGP) was triggered by that sample price. Fixed
with `PriceRecord.is_sample` (Boolean, default False): `seed.py`
marks every seeded record `is_sample=True`, `refresh.py` marks every
fetched record `is_sample=False`, and every lowest-price computation
(`/search`, `/products/{id}`, `/compare`, `/watchlist`, and the alert
check in `refresh.py`) uses LIVE records only. History returns both
kinds, each point flagged with `is_sample`. The falsely-triggered PS5
alert was corrected to `triggered=false` by the one-off
`recompute_alerts.py` (an alert stays triggered only if some LIVE
record ever hit its target). See "Migration note —
`price_records.is_sample`" below for the migration SQL.

## Phase 3 (2026-11-25) — installments, shipping, coupons, back-in-stock alerts, buy-now-or-wait

New tables (created by `init_db()`; SQLite default, PostgreSQL-compatible):
`installment_plans` (product/store, months, monthly_amount, total_amount,
`is_sample`), `store_shipping` (one row per store: fee, free_above,
delivery_days_min/max, `is_sample`), `coupons` (store, code,
discount_type `percent`|`fixed`, discount_value, min_order, expires_at,
`is_sample`, active). `PriceAlert` gained `alert_type` (`price` default |
`back_in_stock`), `store_slug` (NULL = any store), and `target_price`
became nullable (back-in-stock alerts have no price target) — see the
migration note at the end of this file.

### How each feature works

- **Installments.** The crawler extracts the plan from the product page
  (`crawler.extract_installment`): Amazon's "Payment Plans" table — the
  longest 0%-interest plan (total == price) is the canonical one, e.g.
  PS5 12 × 4,208.33 = 50,500 EGP; Vodafone's "4,583 EGP /mo for 12 mos"
  pattern (total stored as monthly × months = 54,996 vs the 54,999 list
  price — the page rounds the monthly down). `refresh.py` stores the live
  plan per product/store (replacing the previous live plan; sample plans
  stay as fallback). The compare endpoint shows the latest plan, live
  preferred, sample flagged (`installment_is_sample`). Seed inserts
  SAMPLE 12- and 24-month plans (monthly = price/months) for every
  sample-price pair.
- **Shipping + delivery.** The crawler extracts what it can read
  confidently (`crawler.extract_shipping`): Amazon "FREE delivery
  Tomorrow, DD Month" → fee 0, 1 day; Jumia "Ready for delivery between
  DD Month and DD Month" → day range, plus `free_above` from "free
  delivery on orders above N EGP". `refresh.py` replaces the store's
  shipping row wholesale with exactly what live extraction found —
  fields it could not find become NULL, never a leftover sample
  estimate presented as live. Compare shows `shipping_fee` (null when
  unknown), `delivery_days_min/max`, and `total_price` = price + fee
  when the fee is known, else null. Seed inserts SAMPLE estimates per
  store (see table below).
- **Coupons.** No live coupon source is wired: store pages show
  bank/card-specific promo codes with per-card terms (e.g. Amazon's
  ADIB10 / QNBC200), not general store coupons, so nothing is scraped
  as a live coupon. Seed inserts one SAMPLE coupon per store
  (`SAMPLE10`, 10% off, `is_sample=True`) — labelled examples, never
  presented as working codes. `POST /coupons` creates a live coupon
  (same no-auth style as the rest of the API); `GET /coupons` and
  `GET /products/{id}/coupons` return active coupons only.
- **Back-in-stock alerts.** `POST /alerts` accepts `alert_type`
  (`price` default, or `back_in_stock`) and optional `store_slug`;
  `target_price` is required for price alerts, optional for
  back-in-stock. In `refresh.py`, before inserting a new live
  `PriceRecord`, the latest live record for that product/store is
  read; if it was out of stock and the new fetch is in stock, matching
  active back-in-stock alerts (that product, that store or any store)
  are marked `triggered=True` (sticky). Price alerts keep their
  existing live-lowest logic untouched (and `_check_alerts` now only
  looks at `alert_type='price'` alerts).
- **Buy-now-or-wait advice.** `GET /products/{id}/advice` uses LIVE
  history points only (last 30 days, `is_sample=False`): `current` =
  latest live lowest, `low_30d` = min live price, `avg_30d` = mean of
  live points, `points_used` = live point count. Verdict: fewer than 3
  points → `unknown` (never a verdict from sample data); current ≤
  low × 1.02 → `buy_now`; current ≥ avg × 1.05 → `wait`; else `fair`.
  Floats are null when there is no live data at all.

### Per-store coverage (verified 2026-11-25, live refresh 10:05 UTC)

| Store | Installments | Shipping | Coupons |
|---|---|---|---|
| Amazon Egypt | **LIVE** — 12-month 0% plan on all 4 live products (PS5 4,208.33 · Philips 605.75 · XM5 999.92 · AirPods 1,166.58 EGP/mo) | **LIVE** — fee 0, delivery 1 day | SAMPLE only (`SAMPLE10`) |
| Jumia Egypt | **Unavailable** — page says "up to 24 months, 0% interest" but gives no monthly amount, so no live plan is stored | **LIVE (partial)** — delivery 4–5 days, free above 500 EGP; fee NOT stored live (page shows "Delivery Fees EGP 40.00" next to "free above 500 EGP" for a 50,000 EGP item — contradictory, so no fee is guessed) | SAMPLE only |
| Vodafone eShop | **LIVE** — iPhone 15: 12 × 4,583 EGP/mo | **SAMPLE** estimate only (fee 50, free above 1,000, 2–4 days) — page shows no fee/days | SAMPLE only |
| Noon / Carrefour / Dream 2000 / Souq | SAMPLE estimates only (no verified product pages / unreachable from this sandbox — see Phase 2 notes) | SAMPLE estimates only | SAMPLE only |

Live rows in the dev DB after the 2026-11-25 refresh: 5 live installment
plans (Amazon ×4 + Vodafone ×1), 2 live shipping rows (Amazon, Jumia);
48 SAMPLE plans + 5 SAMPLE shipping rows + 7 SAMPLE coupons remain as
flagged fallbacks/examples.

### How to test each feature

```bash
# Compare rows with installments/shipping/total (PS5: Amazon live plan +
# free 1-day delivery; Jumia live 4-5 day delivery, sample plan):
curl -s localhost:8000/products/1/compare | python3 -m json.tool
# Advice (PS5 now has 4 live points in 30d -> buy_now):
curl -s localhost:8000/products/1/advice
# Coupons:
curl -s "localhost:8000/coupons?store_slug=jumia-eg"
curl -s localhost:8000/products/1/coupons
curl -s -X POST localhost:8000/coupons -H 'Content-Type: application/json' \
  -d '{"store_slug":"amazon-eg","code":"TEST10","discount_type":"percent","discount_value":10}'
# Back-in-stock alert (no target_price needed):
curl -s -X POST localhost:8000/alerts -H 'Content-Type: application/json' \
  -d '{"product_id":1,"alert_type":"back_in_stock","store_slug":"jumia-eg"}'
curl -s localhost:8000/alerts
# Crawler extras on a real page (installment + shipping in the JSON):
python crawler.py amazon-eg "https://www.amazon.eg/dp/B0CWH9WCWT"
python crawler.py jumia-eg "https://www.jumia.com.eg/sony-playstation-5-slim-console-disc-1-tb-storage-capacity-white-1-year-warranty-135064899.html"
python crawler.py vodafone "https://eshop.vodafone.com.eg/en/prod/iphone-15"
```

Full smoke test (temp product, advice buy_now/wait/fair, sample-proof,
back-in-stock any-store + store-scoped transitions, cleanup): see the
Phase 3 report — script at `/tmp/smoke_phase3.py`, all assertions passed
2026-11-25.

## PostgreSQL

Verified end-to-end 2026-11-25 in this sandbox: PostgreSQL 16
cluster `main` on port 5432, database `pryzo` owned by user `pryzo`
(dev password `pryzo_dev` — local dev only). With
`DATABASE_URL=postgresql+psycopg://pryzo:pryzo_dev@localhost:5432/pryzo`:
`seed.py` created 7 stores / 9 products / 24 SAMPLE records,
`price_alerts.triggered` exists on the fresh tables, `product_urls`
(JSON) round-trips, and the API served `/health`, `/search?q=…` and
`/alerts` (including creating an alert with `triggered: false`)
from Postgres. Re-verified 2026-11-25 after the `is_sample` change:
fresh tables include `price_records.is_sample`, the existing Postgres
DB was migrated (24 rows all SAMPLE, 0 live), a `seed.py` re-run is
idempotent there, and the API served from Postgres returns live-only
lowest prices (PS5 `lowest_price: null`, compare empty — Postgres
holds samples only — while history returns the 3 sample points flagged
`is_sample: true`). To switch production, point `DATABASE_URL` at the
production Postgres and run `seed.py` once; SQLite remains the
default when `DATABASE_URL` is unset.

## Migration note — `price_alerts.triggered`

Added 2026-11-25 (Phase 2): `PriceAlert.triggered`, Boolean,
default False; exposed as `triggered` in `GET /alerts` (and in the
`POST /alerts` response). The existing dev `pryzo.db` was migrated
with `ALTER TABLE price_alerts ADD COLUMN triggered BOOLEAN NOT
NULL DEFAULT 0` (backup at `/tmp/pryzo.db.bak-2026-11-25`, no data
lost — 24 records preserved). `models.init_db()` now also adds the
column itself if it is missing, so a stale DB can no longer crash
refresh/the API (verified by running `init_db()` against the
pre-migration backup: column added, records intact).

## Migration note — `price_records.is_sample`

Added 2026-11-25: `PriceRecord.is_sample`, Boolean, default False.
`seed.py` inserts are `is_sample=True`, `refresh.py` inserts are
`is_sample=False`, and every lowest-price computation / alert check
uses live records only. Fresh tables created by `init_db()` include
the column. For an EXISTING database, add it with:

```sql
-- SQLite and PostgreSQL (same statement):
ALTER TABLE price_records ADD COLUMN is_sample BOOLEAN NOT NULL DEFAULT FALSE;
```

**Gotcha — write `DEFAULT FALSE`, not `DEFAULT 0`.** PostgreSQL
rejects `DEFAULT 0` on a boolean column (`DatatypeMismatch`); SQLite
accepts `FALSE` as 0. Found 2026-11-25 when `_ensure_is_sample_column()`
was first run against Postgres — the same latent bug existed in
`_ensure_triggered_column()` (its `DEFAULT 0` had never actually run
against Postgres, only against SQLite) and was fixed at the same time.

The column alone does not classify old rows — `init_db()` deliberately
does NOT guess which pre-existing rows were samples (no per-pair rule
is correct: e.g. iPhone 15 @ Vodafone has only a live row, no seed
row, so "earliest record per pair is the seed" misclassifies it).
Classify old rows explicitly, per database:

```sql
-- Dev SQLite pryzo.db (backup /tmp/pryzo.db.bak-2026-11-25-is_sample):
-- the 9 live rows are exactly the 2026-11-25 09:04:53 refresh run;
-- everything fetched before that run is a seed SAMPLE.
UPDATE price_records SET is_sample = 1 WHERE fetched_at < '2026-11-25 09:00:00';
-- Result: 24 sample / 9 live / 33 total, no data lost.

-- Dev PostgreSQL pryzo DB: only ever seeded, never refreshed, so all
-- 24 rows are samples.
UPDATE price_records SET is_sample = true;
-- Result: 24 sample / 0 live.
```

The falsely-triggered PS5 alert (target 40,000 EGP, triggered by the
32,999 EGP sample while live lowest was 50,000 EGP) was corrected
with the one-off `recompute_alerts.py`: an alert stays triggered only
if some LIVE record ever reached its target. After the fix the PS5
alert is `triggered=false`; a normal refresh run cannot undo a stale
trigger (stickiness is by design), so use that script if a
sample-caused trigger ever recurs.

## Migration note — Phase 3 (`price_alerts.alert_type` / `store_slug`, nullable `target_price`)

Added 2026-11-25: `PriceAlert.alert_type` (`VARCHAR(20) NOT NULL
DEFAULT 'price'`), `PriceAlert.store_slug` (`VARCHAR(50) NULL`), and
`target_price` changed from NOT NULL to NULLABLE (back-in-stock alerts
have no price target). New tables `installment_plans`,
`store_shipping`, `coupons` are created by `init_db()` via
`create_all`. For an EXISTING database, `init_db()` backfills the two
new columns itself (`_ensure_alert_type_column`,
`_ensure_alert_store_slug_column`, same self-healing pattern as
`triggered`/`is_sample`, `DEFAULT FALSE` rule for booleans) and makes
`target_price` nullable (`_ensure_alert_target_nullable`): PostgreSQL
gets `ALTER TABLE price_alerts ALTER COLUMN target_price DROP NOT
NULL`; SQLite has no ALTER COLUMN, so the table is rebuilt (new table,
copy rows, drop, rename, index recreated) — data preserved. The dev
`pryzo.db` was migrated this way (backup at
`/tmp/pryzo.db.bak-2026-11-25-phase3`, 33 price records + the 1 PS5
alert intact, `target_price` verified nullable afterwards) and the
same `init_db()` was verified against the dev PostgreSQL 16 DB
(`target_price` nullable, new columns present, 3 new tables created,
then seeded: 48 SAMPLE plans / 7 SAMPLE shipping rows / 7 SAMPLE
coupons).

## Deploy to Render (free tier)

See [`DEPLOY.md`](DEPLOY.md) for the full step-by-step (GitHub push →
Render Blueprint → seed via Render Shell → cron-job.org jobs →
verify → point the app at the live URL). Summary:

- `render.yaml` (repo root) declares a free web service (`uvicorn
  main:app --host 0.0.0.0 --port $PORT`, health check `/health`) +
  free PostgreSQL wired as `DATABASE_URL`. **Free Postgres expires
  after 30 days** — upgrade ($6/mo) or replace + re-seed before then.
- Render free has no cron jobs: `POST /admin/refresh` (header
  `X-Refresh-Token: <REFRESH_TOKEN>`, generated by the Blueprint)
  starts a refresh in a background thread and returns 202 at once
  (a full pass takes ~30–90s, over cron-job.org's 30s timeout);
  `GET /admin/refresh/status` returns the last run's counts.
  cron-job.org (free) calls it every 30 min, plus a `GET /health`
  ping every 10 min to keep the free service awake (it sleeps after
  15 min idle).
- On Render the DB is always Postgres (`DATABASE_URL` set by the
  Blueprint); the SQLite `pryzo.db` fallback is local-dev only, and
  the app logs which database it is using at startup (scheme only,
  never credentials).

## Files

- `main.py` — FastAPI app and endpoints (lowest/compare live-only; history returns `is_sample` per point; Phase 3: compare installments/shipping/total, `/advice`, coupons, back-in-stock alerts)
- `models.py` — SQLAlchemy models (`Store`, `Product`, `PriceRecord`, `PriceAlert`, `WatchlistItem`, Phase 3: `InstallmentPlan`, `StoreShipping`, `Coupon`); `init_db()` also backfills the `triggered`, `is_sample`, `alert_type` and `store_slug` columns on stale DBs and makes `price_alerts.target_price` nullable
- `crawler.py` — real page fetcher + price extractor (JSON-LD → meta → Amazon buy-box spans → selectors); UA `PryzoBot/1.0`; Phase 3: `extract_installment` (Amazon 0% plan table, Vodafone `/mo` pattern) and `extract_shipping` (Amazon free delivery + day, Jumia delivery window + free-above) — both return None rather than a guess
- `refresh.py` — scheduled refresh job entrypoint (also checks/sets alert `triggered` against the LIVE lowest); logs to `refresh.log` when run from cron; Phase 3: back-in-stock transition check before each live insert, plus live installment/shipping storage (`_record_live_price` is the single code path per fetch)
- `recompute_alerts.py` — one-off correction: recompute `triggered` from LIVE prices only (see migration note above)
- `seed.py` — idempotent seed: 7 stores, 9 example products with SAMPLE prices (`is_sample=True`), verified product-page URLs where available (see header comment for the per-store verification table); re-runs never touch existing rows, so a live row can never be flipped to sample; Phase 3: SAMPLE installment plans (12/24 mo per sample-price pair), SAMPLE shipping estimates per store, SAMPLE `SAMPLE10` coupon per store
- `requirements.txt` — includes `psycopg[binary]` for the PostgreSQL path
