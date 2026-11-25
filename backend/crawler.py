"""Price crawler for Pryzo.

Fetches a real product page over plain HTTP (``requests``) and extracts the
current price with BeautifulSoup. No store pushes prices to us, so we poll
their public product pages.

Rules this module follows:
- Sends an identifying bot User-Agent, ``PryzoBot/1.0`` (plain string, no
  contact URL -- we own no pryzo domain yet, so none is invented).
  Jumia's robots.txt asks bots to identify themselves and says "bots with
  fake user-agent will be blocked"; the previous desktop-browser UA was
  exactly what Jumia says it blocks, and Jumia returned HTTP 403 on every
  fetch with it (verified 2026-11-25). The robots.txt check in this module
  is evaluated against this same UA, so it is now judged as the bot.
- Respects robots.txt (``urllib.robotparser``): if a store disallows the
  URL for our User-Agent, the fetch is skipped -- never worked around.
- Sleeps at least 2 seconds between requests (politeness delay).
- Tries JSON-LD ``offers.price`` first, then meta tags, then Amazon's
  structured buy-box price spans (whole + fraction -- the offscreen
  text drops the decimal point), then common price selectors, then a
  currency-amount regex as a last resort (never on Amazon pages, where
  it would pick up recommendation prices).
- Never invents a price. On any block (timeout, 403, CAPTCHA / bot-check
  page, no price found) it returns ``None`` and logs the reason.

CLI usage::

    python crawler.py <store_slug> <url>
    python crawler.py jumia-eg "https://www.jumia.com.eg/..."

First targets: Jumia Egypt (jumia.com.eg) and Amazon Egypt (amazon.eg).

NOTE (2026-11-25, observed): Jumia's robots.txt header says scraping is
permitted only if the bot's User-Agent clearly identifies it as a bot (with
an owner URL/contact), and that "bots with fake user-agent will be blocked".
The previous desktop-browser UA was blocked with HTTP 403 on every fetch
(verified 2026-11-25). Switched to the identifying bot UA ``PryzoBot/1.0``
(plain string only -- no contact URL invented, we own no pryzo domain yet)
and re-testing Jumia with it.
"""

from __future__ import annotations

import json
import logging
import re
import sys
import time
from urllib.parse import urlparse
from urllib.robotparser import RobotFileParser

import requests
from bs4 import BeautifulSoup

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("pryzo.crawler")

USER_AGENT = "PryzoBot/1.0"

# Minimum delay between two HTTP requests, in seconds.
MIN_DELAY_SECONDS = 2.0

# How long to wait for a store to answer before giving up.
REQUEST_TIMEOUT_SECONDS = 20

# Phrases that indicate a bot-check / CAPTCHA / block page.
BLOCK_MARKERS = (
    "captcha",
    "are you a robot",
    "robot check",
    "verify you are human",
    "access denied",
    "unusual traffic",
    "please verify",
    "bot detection",
    "automated access",
)

# Store slug -> base URL, used for robots.txt lookups.
STORE_BASE_URLS = {
    "jumia-eg": "https://www.jumia.com.eg",
    "amazon-eg": "https://www.amazon.eg",
    "noon": "https://www.noon.com/egypt-en",
    "dream2000": "https://dream2000.com",
    "vodafone": "https://eshop.vodafone.com.eg",
    "carrefour": "https://www.carrefouregypt.com",
    "souq": "https://egypt.souq.com",
}

# CSS selectors tried (in order) after JSON-LD and meta tags.
# NOTE: the broad "span.a-price span.a-offscreen" selector is deliberately
# NOT here: on amazon.eg the offscreen text concatenates whole+fraction
# without the decimal point ("EGP11,99900"), and on pages whose buy box
# is empty (currently unavailable) the only a-price spans on the page
# belong to "Customers also viewed" recommendations -- the crawler once
# stored a recommendation's price as the product's (2026-11-25,
# amazon.eg/dp/B0CWRLJYGJ). Amazon prices are read only from the
# buy-box containers via _price_from_amazon_spans() instead.
PRICE_SELECTORS = [
    # Amazon Egypt (buy-box only)
    "#priceblock_ourprice",
    "#priceblock_dealprice",
    # Jumia Egypt
    "span.-b.-ltr.-tal.-fs24",
    "span.prc",
    "[data-price]",
    # Generic / common
    "[itemprop='price']",
    "meta[itemprop='price']",
    ".price",
    ".product-price",
    ".current-price",
    ".price-now",
    "span.price",
]

# Containers that hold the product's own buy-box price on Amazon. Prices
# anywhere else on an Amazon page (recommendations, "also viewed", ads)
# must never be read as this product's price.
AMAZON_BUY_BOX_SELECTORS = (
    "#corePriceDisplay_desktop_feature_div",
    "#priceblock_ourprice",
    "#priceblock_dealprice",
    "#buybox",
    "#desktop_buybox",
)

_last_request_at = 0.0
_robot_parsers: dict[str, RobotFileParser | None] = {}


def _polite_wait() -> None:
    """Enforce at least MIN_DELAY_SECONDS between requests."""
    global _last_request_at
    elapsed = time.monotonic() - _last_request_at
    if elapsed < MIN_DELAY_SECONDS:
        time.sleep(MIN_DELAY_SECONDS - elapsed)
    _last_request_at = time.monotonic()


def _get_robot_parser(base_url: str) -> RobotFileParser | None:
    """Fetch (once) and cache the robots.txt parser for a store origin.

    Fetched with ``requests`` (same proxy/session behaviour as page
    fetches) and parsed with ``RobotFileParser.parse``. Note:
    ``RobotFileParser.read()`` uses ``urllib`` and treats *any* fetch
    failure as "disallow everything", which wrongly blocks stores when
    robots.txt itself is briefly unreachable or rate-limited -- so we fetch
    it ourselves. If robots.txt cannot be fetched at all, we return
    ``None`` (fail open / allow) and log a warning, per RFC 9309
    section 2.3 (4xx/5xx on robots.txt means no restrictions are known).
    Returning ``None`` matters: an *unparsed* ``RobotFileParser``
    answers ``can_fetch() == False`` for every URL in this Python, so
    caching the empty parser would silently block the whole store
    (observed 2026-11-25 with Noon, whose robots.txt times out from
    this sandbox).
    """
    origin = f"{urlparse(base_url).scheme}://{urlparse(base_url).netloc}"
    if origin in _robot_parsers:
        return _robot_parsers[origin]
    rp = RobotFileParser()
    rp.set_url(origin + "/robots.txt")
    try:
        resp = requests.get(
            origin + "/robots.txt",
            headers={"User-Agent": USER_AGENT},
            timeout=REQUEST_TIMEOUT_SECONDS,
        )
        if resp.status_code == 200:
            rp.parse(resp.text.splitlines())
        else:
            log.warning(
                "robots.txt for %s returned HTTP %s; proceeding (no rules known)",
                origin,
                resp.status_code,
            )
            _robot_parsers[origin] = None
            return None
    except requests.RequestException as exc:
        log.warning(
            "Could not read robots.txt for %s: %s; proceeding (no rules known)",
            origin,
            exc,
        )
        _robot_parsers[origin] = None
        return None
    _robot_parsers[origin] = rp
    return rp


def robots_allowed(url: str) -> bool:
    """True if robots.txt allows our User-Agent to fetch this URL."""
    try:
        rp = _get_robot_parser(url)
        if rp is None:
            return True
        return rp.can_fetch(USER_AGENT, url)
    except Exception as exc:
        log.warning("robots.txt check failed for %s: %s (allowing)", url, exc)
        return True


def _parse_price_text(text: str) -> float | None:
    """Extract a numeric price from text like 'EGP 32,999.00' or '32,999'."""
    if not text:
        return None
    cleaned = text.replace("\u00a0", " ").strip()
    # Prefer a number that follows a currency marker when present.
    m = re.search(r"(?:EGP|LE|E£|ج\.?م\.?|£)\s*([\d,]+(?:\.\d{1,2})?)", cleaned)
    if not m:
        m = re.search(r"([\d,]+(?:\.\d{1,2})?)", cleaned)
    if not m:
        return None
    raw = m.group(1)
    # Guard against Amazon-style concatenated whole+fraction text, e.g.
    # an offscreen span reading "EGP11,99900" (whole "11,999" + fraction
    # "00" with the decimal point dropped). A properly grouped number
    # with commas and no decimal point always ends in a 3-digit group;
    # "11,99900" ends in a 5-digit group, so it is not a real price.
    # (Observed 2026-11-25 on amazon.eg/dp/B0CWRLJYGJ: without this
    # guard the crawler stored 1,199,900 EGP for an 11,999 EGP item.)
    if "," in raw and "." not in raw:
        last_group = raw.rsplit(",", 1)[-1]
        if len(last_group) != 3:
            return None
    try:
        value = float(raw.replace(",", ""))
    except ValueError:
        return None
    # Reject absurd values (likely a SKU, rating count, etc.).
    if value <= 0 or value > 10_000_000:
        return None
    return value


def _price_from_json_ld(soup: BeautifulSoup) -> tuple[float | None, bool]:
    """Look for schema.org Product/Offer JSON-LD with offers.price."""
    for script in soup.find_all("script", type="application/ld+json"):
        raw = script.string or script.get_text() or ""
        if not raw.strip():
            continue
        try:
            data = json.loads(raw)
        except (json.JSONDecodeError, ValueError):
            continue
        items = data if isinstance(data, list) else [data]
        for item in items:
            if not isinstance(item, dict):
                continue
            # Some pages nest the Product under @graph.
            if "@graph" in item and isinstance(item["@graph"], list):
                items.extend(item["@graph"])
                continue
            offers = item.get("offers")
            if isinstance(offers, list):
                offers = offers[0] if offers else None
            if isinstance(offers, dict):
                price = offers.get("price")
                if price is not None:
                    try:
                        value = float(str(price).replace(",", ""))
                    except ValueError:
                        continue
                    if value > 0:
                        availability = str(offers.get("availability", "")).lower()
                        in_stock = "outofstock" not in availability
                        return value, in_stock
    return None, True


def _price_from_meta(soup: BeautifulSoup) -> float | None:
    """Meta tags: og:price:amount / product:price:amount."""
    for key in ("product:price:amount", "og:price:amount"):
        tag = soup.find("meta", property=key) or soup.find("meta", attrs={"name": key})
        if tag and tag.get("content"):
            value = _parse_price_text(tag["content"])
            if value:
                return value
    return None


def _price_from_amazon_spans(soup: BeautifulSoup) -> float | None:
    """Read an Amazon price from the structured whole/fraction spans.

    Amazon renders a price as ``<span class="a-price"><span
    class="a-price-whole">11,999</span><span
    class="a-price-fraction">00</span></span>``; the offscreen text
    concatenates them without the decimal point, so only the structured
    spans give the right value. Only spans inside the buy-box
    containers are read -- if the buy box is empty (currently
    unavailable) there is no price to report, even though the page
    still shows prices for recommended products.
    """
    for container_sel in AMAZON_BUY_BOX_SELECTORS:
        for container in soup.select(container_sel):
            for el in container.select("span.a-price"):
                whole = el.select_one("span.a-price-whole")
                frac = el.select_one("span.a-price-fraction")
                if not whole or not frac:
                    continue
                try:
                    value = float(
                        whole.get_text(strip=True).replace(",", "")
                        + "."
                        + frac.get_text(strip=True)
                    )
                except ValueError:
                    continue
                if 0 < value <= 10_000_000:
                    return value
    return None


def _price_from_selectors(soup: BeautifulSoup) -> float | None:
    for selector in PRICE_SELECTORS:
        for el in soup.select(selector):
            text = el.get("content") or el.get_text(" ", strip=True)
            value = _parse_price_text(text or "")
            if value:
                return value
    return None


# ---------------------------------------------------------------------------
# Installments + shipping (Phase 3, 2026-11-25)
# ---------------------------------------------------------------------------
# Verified against REAL pages with the crawler CLI before any of this was
# stored as live (probe 2026-11-25, see backend/README.md):
# - Amazon EG: a "Payment Plans" table, rows like "12 months EGP
#   4,208.33 EGP 50,500.00" (months, monthly, total). Rows whose total
#   equals the product price are 0% plans; the longest 0% plan is the
#   canonical one (lowest monthly at no extra cost). Verified on PS5
#   (12 x 4,208.33 = 50,500), AirPods Pro 2 (12 x 1,166.58 = 13,999),
#   Philips HD9270 (12 x 605.75 = 7,269).
# - Vodafone eShop: "4,583 EGP /mo for 12 mos installment" -- one plan,
#   total = monthly x months (54,996 vs the 54,999 list price: the
#   page rounds the monthly down, so the stored total is the computed
#   monthly x months, not the list price).
# - Jumia EG: "Buy now and pay later with 0% interest ... for up to 24
#   months" -- a term with NO monthly amount, so no live plan is stored.
#   Never store a monthly amount computed from the price as live.
# - Amazon delivery: "FREE delivery Tomorrow, 26 November" -- fee 0,
#   1 day. Jumia: "Ready for delivery between 29 November and 30
#   November" -- 4-5 days from the 25 Nov fetch; its fee is NOT stored
#   live because the page contradicts itself ("Delivery Fees EGP 40.00"
#   next to "free delivery on orders above 500 EGP" for a 50,000 EGP
#   item), so no fee is guessed. Vodafone shows no fee/days at all.
# Anything these extractors cannot find with a clear pattern returns
# None -- never a guess stored as live.

_MONTH_NAME_TO_NUM = {
    name: num
    for num, name in enumerate(
        ["january", "february", "march", "april", "may", "june", "july",
         "august", "september", "october", "november", "december"],
        start=1,
    )
}
_MONTH_NAME_TO_NUM.update(
    {name[:3]: num for name, num in _MONTH_NAME_TO_NUM.items()}
)


def _days_until(day: int, month_name: str, today) -> int | None:
    """Days from ``today`` (a date) to the next ``day month_name`` date."""
    from datetime import date as _date

    month = _MONTH_NAME_TO_NUM.get(month_name.lower())
    if month is None:
        return None
    try:
        target = _date(today.year, month, day)
    except ValueError:
        return None
    if target < today:
        try:
            target = _date(today.year + 1, month, day)
        except ValueError:
            return None
    return (target - today).days


def extract_installment(soup: BeautifulSoup, price: float | None) -> dict | None:
    """Best single installment plan from a product page, or None.

    Returns ``{"months": int, "monthly_amount": float,
    "total_amount": float}``. Prefers the longest 0%-interest plan
    (Amazon payment-plans table: total == price); otherwise the
    ``X EGP /mo for N mos`` pattern (Vodafone). Never invents a plan:
    a term with no monthly amount (Jumia's "up to 24 months") yields
    nothing, and a computed price/months split is never stored as live.
    """
    text = re.sub(r"\s+", " ", soup.get_text(" ", strip=True))
    if price:
        rows = re.findall(
            r"(\d+)\s*months?\s+EGP\s*([\d,]+\.\d{2})\s+EGP\s*([\d,]+\.\d{2})",
            text,
        )
        zero_interest: dict[int, tuple[float, float]] = {}
        for months_s, monthly_s, total_s in rows:
            months = int(months_s)
            monthly = float(monthly_s.replace(",", ""))
            total = float(total_s.replace(",", ""))
            # 0% plan: total equals the product price (exact on Amazon;
            # allow 1 EGP of rounding slack, no more).
            if abs(total - price) <= 1.0 and 0 < monthly <= price:
                zero_interest.setdefault(months, (monthly, total))
        if zero_interest:
            months = max(zero_interest)
            monthly, total = zero_interest[months]
            return {
                "months": months,
                "monthly_amount": round(monthly, 2),
                "total_amount": round(total, 2),
            }
    # Generic "X EGP /mo for N mos" (Vodafone eShop).
    m = re.search(
        r"([\d,]+(?:\.\d+)?)\s*EGP\s*/mo(?:nth)?\s*for\s*(\d+)\s*mos?",
        text,
    )
    if m:
        monthly = float(m.group(1).replace(",", ""))
        months = int(m.group(2))
        if monthly > 0 and months > 0:
            return {
                "months": months,
                "monthly_amount": round(monthly, 2),
                "total_amount": round(monthly * months, 2),
            }
    return None


def extract_shipping(soup: BeautifulSoup) -> dict | None:
    """Best-effort shipping/delivery info from a product page, or None.

    Returns a dict with any of ``fee``, ``free_above``,
    ``delivery_days_min``, ``delivery_days_max`` that could be read
    confidently; fields that could not be read are omitted (stored as
    NULL, never guessed). Amazon: "FREE delivery Tomorrow, DD Month"
    -> fee 0.0, 1 day. Jumia: "Ready for delivery between DD Month
    and DD Month" -> day range; ``free_above`` from "free delivery on
    orders above N EGP"; fee deliberately NOT read (the page shows a
    "Delivery Fees EGP 40.00" that contradicts free-above-500 for a
    50,000 EGP item).
    """
    from datetime import date as _date

    text = re.sub(r"\s+", " ", soup.get_text(" ", strip=True))
    today = _date.today()
    out: dict = {}

    # Amazon: FREE delivery + a delivery day.
    if re.search(r"FREE delivery", text):
        out["fee"] = 0.0
        m = re.search(
            r"FREE delivery\s+(Tomorrow,?\s*\d{1,2}\s+[A-Za-z]+)", text
        )
        if m and "Tomorrow" in m.group(1):
            out["delivery_days_min"] = 1
            out["delivery_days_max"] = 1
        else:
            m = re.search(
                r"FREE delivery[^.]{0,60}?(\d{1,2})\s+([A-Za-z]+)", text
            )
            if m:
                days = _days_until(int(m.group(1)), m.group(2), today)
                if days is not None and 0 <= days <= 30:
                    out["delivery_days_min"] = days
                    out["delivery_days_max"] = days

    # Jumia: "Ready for delivery between 29 November and 30 November".
    m = re.search(
        r"Ready for delivery between\s+(\d{1,2})\s+([A-Za-z]+)\s+and\s+"
        r"(\d{1,2})\s+([A-Za-z]+)",
        text,
    )
    if m:
        d_min = _days_until(int(m.group(1)), m.group(2), today)
        d_max = _days_until(int(m.group(3)), m.group(4), today)
        if d_min is not None and d_max is not None and 0 <= d_min <= d_max <= 30:
            out["delivery_days_min"] = d_min
            out["delivery_days_max"] = d_max
    m = re.search(
        r"free delivery on orders above\s+([\d,]+)\s*EGP", text, flags=re.I
    )
    if m:
        try:
            out["free_above"] = float(m.group(1).replace(",", ""))
        except ValueError:
            pass

    return out or None


def fetch_product_extras(soup: BeautifulSoup, price: float | None) -> dict:
    """Installment + shipping extraction for an already-fetched page.

    Returns ``{"installment": dict | None, "shipping": dict | None}``.
    Used by refresh.py (via fetch_price) and testable on its own.
    """
    return {
        "installment": extract_installment(soup, price),
        "shipping": extract_shipping(soup),
    }


def _looks_blocked(status_code: int, html: str) -> str | None:
    """Return a human-readable block reason, or None if the page looks real."""
    if status_code in (403, 429, 503):
        return f"HTTP {status_code} (store refused the request)"
    lowered = html[:20000].lower()
    for marker in BLOCK_MARKERS:
        if marker in lowered:
            return f"bot-check / block page detected ({marker!r} in page)"
    return None


def fetch_price(store_slug: str, url: str) -> dict | None:
    """Fetch one product page and extract its current price.

    Returns ``{"price": float, "currency": "EGP", "in_stock": bool,
    "url": str, "installment": dict | None, "shipping": dict | None}``
    on success, or ``None`` (with the reason logged) when the page
    could not be fetched or no price could be found. Never returns a
    guessed or fake price. ``installment`` / ``shipping`` are
    best-effort extras (Phase 3, see extract_installment /
    extract_shipping): ``None`` when the page shows no usable info.
    """
    if not robots_allowed(url):
        log.warning("Skipping %s: disallowed by robots.txt", url)
        return None

    _polite_wait()
    headers = {
        "User-Agent": USER_AGENT,
        "Accept-Language": "en-EG,en;q=0.9,ar;q=0.8",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
    }
    try:
        resp = requests.get(url, headers=headers, timeout=REQUEST_TIMEOUT_SECONDS)
    except requests.Timeout:
        log.warning("Timeout fetching %s", url)
        return None
    except requests.RequestException as exc:
        log.warning("Request failed for %s: %s", url, exc)
        return None

    blocked = _looks_blocked(resp.status_code, resp.text)
    if blocked:
        log.warning("Blocked fetching %s: %s", url, blocked)
        return None
    if resp.status_code != 200:
        log.warning("HTTP %s fetching %s", resp.status_code, url)
        return None

    soup = BeautifulSoup(resp.text, "html.parser")

    price: float | None = None
    in_stock = True

    # 1) JSON-LD offers.price
    price, in_stock = _price_from_json_ld(soup)
    if price:
        log.info("Price via JSON-LD: %s EGP (%s)", price, url)

    # 2) Meta tags
    if not price:
        price = _price_from_meta(soup)
        if price:
            log.info("Price via meta tag: %s EGP (%s)", price, url)

    # 3) Amazon structured buy-box price spans
    if not price:
        price = _price_from_amazon_spans(soup)
        if price:
            log.info("Price via Amazon buy-box spans: %s EGP (%s)", price, url)

    # 4) Common price selectors
    if not price:
        price = _price_from_selectors(soup)
        if price:
            log.info("Price via selector: %s EGP (%s)", price, url)

    # 5) Last resort: first EGP amount in page text. Skipped on Amazon
    # pages: if structured extraction found no buy-box price, the page
    # is showing an unavailable item and every EGP amount on it belongs
    # to recommendations or other sellers (see B0CWRLJYGJ, 2026-11-25).
    if not price and not soup.select("span.a-price"):
        text = soup.get_text(" ", strip=True)
        m = re.search(
            r"EGP\s*([\d,]+(?:\.\d{1,2})?)", text, flags=re.IGNORECASE
        )
        if m:
            price = _parse_price_text(m.group(0))
            if price:
                log.info("Price via EGP regex: %s EGP (%s)", price, url)

    if not price:
        log.warning(
            "No price found on %s (page fetched OK, %d bytes)", url, len(resp.text)
        )
        return None

    # Phase 3: best-effort installment + shipping from the same page.
    # Either may be None (not found / not offered); None is never
    # stored as live data, it just means "no live info for this store".
    extras = fetch_product_extras(soup, price)
    if extras["installment"]:
        log.info("Installment: %s (%s)", extras["installment"], url)
    if extras["shipping"]:
        log.info("Shipping: %s (%s)", extras["shipping"], url)
    return {
        "price": price,
        "currency": "EGP",
        "in_stock": in_stock,
        "url": url,
        "installment": extras["installment"],
        "shipping": extras["shipping"],
    }


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print("Usage: python crawler.py <store_slug> <url>")
        print("Example: python crawler.py jumia-eg \"https://www.jumia.com.eg/...\"")
        return 2
    store_slug, url = argv[1], argv[2]
    result = fetch_price(store_slug, url)
    if result is None:
        print(f"NO PRICE: could not extract a price from {url}")
        return 1
    print(json.dumps(result, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
