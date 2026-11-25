# Deploy Pryzo Backend to Koyeb (Free Instance) + Neon Postgres (Free)

Use this only if Mohamed picks Koyeb. Read the warning first — it
changes the choice he was offered.

## ⚠️ Correction: Koyeb is NOT card-free anymore

Koyeb's own Pricing FAQ (koyeb.com/docs/faqs/pricing, checked
2026-11-25) says: "We require a credit card to prevent fraud and
abuse. We verify the card you enter by placing a **$29
pre-authorization hold** and immediately canceling it. Depending on
your card issuer, the hold will disappear immediately, or after
between 7 and 21 days." Independent free-tier trackers checked in
Nov 2026 say the same (card-free Hobby plan removed Feb 2026).

So the real choice is NOT "Render needs a card, Koyeb doesn't".
Both need a card — Render verifies with a temporary **$1**
authorization, Koyeb with a **$29** hold. Render is the cheaper
verification to attempt, especially since Mohamed's Vodafone card
was already declined on Google Play (it may fail verification on
either host).

What IS genuinely card-free: **Neon Postgres** — Free plan, $0,
permanent, no credit card required, 1 GB storage + 100 CU-hours/month
per project (neon.com/pricing, checked 2026-11-25). Use Neon for the
database either way: it also fixes Render's real flaw (its free
database is deleted 30 days after creation).

## What is already done

- `Dockerfile` (repo root, committed + pushed 2026-11-25) —
  Python 3.12-slim, installs `backend/requirements.txt`, runs
  `uvicorn main:app` on `$PORT` (Koyeb sets it; defaults to 8000).
  No local Docker here, so the image was NOT built/tested — Koyeb
  builds it on first deploy; if the build fails, the log will say
  which step.
- `backend/models.py` — fixed 2026-11-25: a `DATABASE_URL` starting
  with `postgres://` (what Render and Neon both hand out) used to
  crash the app at startup with
  `NoSuchModuleError: Can't load plugin: sqlalchemy.dialects:postgres`.
  It is now normalized to `postgresql://` at import; verified with a
  `postgres://` URL (engine loads, psycopg driver) and with the
  SQLite default untouched.
- `POST /admin/refresh` (token-guarded) and `GET /health` already
  exist in `backend/main.py`; the refresh runs in a background thread
  and returns 202 at once (see `backend/DEPLOY.md` step 5 for why).

## 1. Neon database (free, no card, permanent)

1. Create a free account at neon.com (email or GitHub, no card).
2. New project → database `pryzo` → copy the connection string.
   It looks like `postgres://user:pass@ep-xxx.neon.tech/pryzo?sslmode=require`.
   The code fix above handles the `postgres://` prefix, so paste it
   as-is; keep `sslmode=require`.
3. This database does NOT expire after 30 days (unlike Render's
   free one). Limits: 1 GB storage, 100 CU-hours/month; compute
   sleeps after 5 idle minutes and wakes on the next query.

## 2. Koyeb service (needs a card — $29 hold)

1. Create an account at koyeb.com (GitHub sign-in works) and add a
   card when asked — the $29 hold is cancelled immediately, but the
   bank can take 7–21 days to release it.
2. Create a Web Service from the GitHub repo `mohgaber/pryzo`:
   builder **Dockerfile**, Dockerfile path `Dockerfile` (repo
   root), instance type **free** (512 MB RAM, 0.1 vCPU), region Frankfurt
   or Washington, D.C., health check path `/health`.
3. Environment variables:
   - `DATABASE_URL` = the Neon connection string from step 1.
   - `REFRESH_TOKEN` = generate a long random value (e.g.
     `openssl rand -hex 32`) and save it — the same value goes into
     the cron-job.org refresh job below.
4. Deploy. First build takes a few minutes; copy the service URL
   (`https://<name>-<id>.koyeb.app`).

## 3. Seed the production database (once)

In the Koyeb console, open the service → **Console** (or use the
Koyeb CLI) and run:

```bash
python seed.py
```

`seed.py` is idempotent and inserts the 7 stores, 9 products and
24 **SAMPLE** prices (`is_sample=True`). Live prices arrive via the
refresh job; the first scheduled refresh adds them.

## 4. Schedule the refresh — cron-job.org (free, no card)

Same two jobs as in `backend/DEPLOY.md` step 5, with the Koyeb URL:

| Job | URL | Method | Schedule |
|---|---|---|---|
| `pryzo-keep-awake` | `https://<your-service>.koyeb.app/health` | GET | every 50 minutes |
| `pryzo-refresh` | `https://<your-service>.koyeb.app/admin/refresh` | POST | every 30 minutes, header `X-Refresh-Token: <REFRESH_TOKEN>` |

Why every 50 minutes for keep-awake: the free instance scales to
zero after 1 hour without traffic; a ping inside the hour keeps it
warm (cold start is only 1–5 s if it does sleep). The refresh job
is the same 30-minute cadence as the Render plan.

## 5. Verify

```bash
BASE=https://<your-service>.koyeb.app   # exact URL from the dashboard
curl -s $BASE/health                    # {"status": "ok"}
curl -s "$BASE/search?q=playstation"    # products; lowest_price is LIVE-only
curl -s $BASE/products/1/compare       # per-store LIVE prices after first refresh
```

## 6. Point the Flutter app at it

Same step as the Render plan: set the API base URL in the app to
the Koyeb service URL and rebuild the APK (`~/workspace/pryzo.apk`).
Until then the phone app keeps showing sample data with the banner.
