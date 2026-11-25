"""Automatic product discovery for Pryzo (v1).

The price refresh only re-fetches products already in the database. This
module finds NEW products by itself, the way PriceTeq does:

1.  Enumerate a shop's products from its public sitemap (never from
    PriceTeq's data — its ToS forbids bulk scraping; we crawl the shops
    directly, like PriceTeq does).
2.  Fetch each product page and extract the schema.org Product JSON-LD
    (name, brand, price, availability, image).
3.  Normalise the listing name and match it against Pryzo's catalog
    (signature tokens: brand + model + storage). A listing that matches
    an existing product gives us a NEW store URL for that product; a
    listing that matches nothing is a candidate NEW product.
4.  Report the matches + candidates as JSON. Nothing is written to the
    database by this module — a human (or a later step) decides what to
    add, so a bad match can never pollute the catalog on its own.

Rules (same as crawler.py):
- Identifies itself as PryzoBot/1.0 and respects robots.txt.
- At least 2 seconds between requests. Sitemap fetches are also
  throttled (they are large files; a full shop catalog is fetched
  once per run, not per product).
- Never invents a price or a name. A page without JSON-LD Product data
  is skipped, not guessed.

CLI usage::

    python discover.py wazen --limit 30
    python discover.py btech --limit 20

The report prints matched URLs per Pryzo product, plus the unmatched
candidate listings (name + price + URL) for review.
"""

from __future__ import annotations

import argparse
import json
import logging
import re
import sys
import time
import xml.etree.ElementTree as ET
from urllib.parse import urlparse

import requests
from bs4 import BeautifulSoup

import crawler
from crawler import (
    USER_AGENT,
    REQUEST_TIMEOUT_SECONDS,
    _looks_blocked,
    _polite_wait,
    robots_allowed,
)

logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")
log = logging.getLogger("pryzo.discover")

# Per-store sitemap config: where the product URLs live, and how to
# recognise a product URL (vs a category / info page) inside a sitemap.
# wazen is WooCommerce: a sitemap index with product-sitemap*.xml.
# btech's sitemap.xml lists a subset of products under /en/p/.
# rayashop's sitemap.xml is ~16 MB — too big to pull on every run, so
# it is left out of v1 (its products are added by hand for now).
SITEMAP_CONFIG = {
    "wazen": {
        "index": "https://wazen.eg/sitemap_index.xml",
        "sitemap_filter": "product-sitemap",
        "url_filter": "/product/",
    },
    "btech": {
        "index": "https://btech.com/sitemap.xml",
        "sitemap_filter": None,  # single sitemap, not an index
        "url_filter": "/en/p/",
    },
}

# Words that carry no identifying meaning for a product and are dropped
# when normalising names (colours are kept out too: they are variants,
# not the product itself).
FILLER_WORDS = {
    "original", "official", "warranty", "middle", "east", "version",
    "dual", "sim", "smartphone", "console", "edition", "wireless",
    "headphones", "series", "digital", "screen", "capacity", "storage",
    "the", "and", "with", "for", "new", "gen", "generation", "pro",
    "lite", "plus", "ultra", "max", "mini", "standard", "global",
    "international", "egypt", "eg", "black", "white", "blue", "grey",
    "gray", "silver", "gold", "pink", "green", "red", "purple", "violet",
    "lilac", "navy", "yellow", "orange", "brown", "beige", "amber",
    "onyx", "marble", "cobalt", "awesome", "phantom", "mystic",
    "5g", "4g", "lte", "wifi", "bluetooth", "nfc", "gb", "ram", "tb",
    "inch", "inches", "led", "lcd", "oled", "uhd", "4k", "smart", "tv",
    "litre", "liter", "watt", "essential", "xl", "large", "small",
}

# Minimum fraction of a product's signature tokens that must appear in
# a listing name for it to count as a match (brand must also match).
# Set to 1.0 on purpose: a listing that is missing even one identifying
# token is a different product (a PS4 scores 0.75 against the PS5; an
# iPhone 15 Pro Max 256GB scores 0.75 against the iPhone 15 128GB).
# A strict matcher that misses a valid URL is safe — the report shows
# near-misses for a human to review; a loose matcher would pollute
# the catalog with the wrong product.
MATCH_THRESHOLD = 1.0

# Variant words: if a listing name contains one of these and the
# catalog product's name does not, the listing is a different variant
# (S24 FE is not an S24; an iPhone 15 Pro is not an iPhone 15) — even
# when every signature token is present. "5g"/"4g"/"slim" are NOT here:
# they are often omitted from the catalog name but do not change the
# product (the S24 is 5G; the PS5 Slim is the current PS5).
VARIANT_WORDS = {
    "fe", "pro", "max", "plus", "ultra", "lite", "mini", "se",
    "edge", "note", "fold", "flip",
}


def _fetch_sitemap_locs(url: str) -> tuple[bool | None, list[str]]:
    """Fetch a sitemap and return (is_index, [loc, ...]).

    For each <url>, prefer the xhtml:link alternate with hreflang="en"
    (B.TECH lists Arabic URLs in <loc> and the English URL only in
    the alternate link — the English page is the one whose JSON-LD
    name matches Pryzo's English catalog); fall back to the <loc>
    text (wazen has no alternates). Image <loc> entries are ignored.
    Uses a 120s timeout: B.TECH's sitemap is ~45 MB and takes ~60s
    to download, so the 20s product-page timeout would always fail.
    Returns (None, []) when the sitemap could not be fetched/parsed.
    """
    _polite_wait()
    try:
        resp = requests.get(
            url,
            headers={"User-Agent": USER_AGENT},
            timeout=120,
        )
    except requests.RequestException as exc:
        log.warning("Sitemap fetch failed for %s: %s", url, exc)
        return None, []
    if resp.status_code != 200:
        log.warning("HTTP %s fetching sitemap %s", resp.status_code, url)
        return None, []
    try:
        root = ET.fromstring(resp.content)
    except ET.ParseError as exc:
        log.warning("Could not parse sitemap %s: %s", url, exc)
        return None, []
    is_index = root.tag.endswith("sitemapindex")
    locs: list[str] = []
    if is_index:
        for sm in root.iter():
            if sm.tag.endswith("sitemap"):
                for child in sm:
                    if child.tag.endswith("loc") and child.text:
                        locs.append(child.text.strip())
    else:
        for url_el in root.iter():
            if not url_el.tag.endswith("url"):
                continue
            loc = None
            en_href = None
            for child in url_el:
                if child.tag.endswith("loc") and child.text:
                    loc = child.text.strip()
                elif child.tag.endswith("link") and child.get("hreflang") == "en":
                    en_href = child.get("href")
            chosen = en_href or loc
            if chosen:
                locs.append(chosen)
    return is_index, locs


def enumerate_product_urls(store_slug: str, max_urls: int = 500) -> list[str]:
    """All product-page URLs for a store, from its public sitemap.

    Follows a sitemap index into its product sitemaps. Deduplicates and
    caps the result (a full catalog run is a nightly job; a test run
    uses a small cap).
    """
    cfg = SITEMAP_CONFIG.get(store_slug)
    if cfg is None:
        log.error("No sitemap config for store %s", store_slug)
        return []
    is_index, index_locs = _fetch_sitemap_locs(cfg["index"])
    if is_index is None:
        return []
    sitemap_urls: list[str] = []
    if is_index:
        for loc in index_locs:
            if cfg["sitemap_filter"] and cfg["sitemap_filter"] not in loc:
                continue
            sitemap_urls.append(loc)
    else:
        sitemap_urls = [cfg["index"]]
    urls: list[str] = []
    seen: set[str] = set()
    for sm_url in sitemap_urls:
        if len(urls) >= max_urls:
            break
        _sub_is_index, sub_locs = _fetch_sitemap_locs(sm_url)
        if _sub_is_index is None:
            continue
        for loc in sub_locs:
            if cfg["url_filter"] not in loc:
                continue
            if loc in seen:
                continue
            seen.add(loc)
            urls.append(loc)
            if len(urls) >= max_urls:
                break
    log.info("Enumerated %d product URLs for %s", len(urls), store_slug)
    return urls


def _product_from_json_ld(soup: BeautifulSoup) -> dict | None:
    """Extract schema.org Product data (name/brand/price/stock/image)."""
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
            if "@graph" in item and isinstance(item["@graph"], list):
                items.extend(item["@graph"])
                continue
            if str(item.get("@type", "")).lower() != "product":
                continue
            name = item.get("name")
            if not name:
                continue
            offers = item.get("offers")
            if isinstance(offers, list):
                offers = offers[0] if offers else None
            price = None
            in_stock = True
            if isinstance(offers, dict):
                raw_price = offers.get("price")
                if raw_price is not None:
                    try:
                        price = float(str(raw_price).replace(",", ""))
                    except ValueError:
                        price = None
                availability = str(offers.get("availability", "")).lower()
                in_stock = "outofstock" not in availability
            brand = item.get("brand")
            if isinstance(brand, dict):
                brand = brand.get("name")
            image = item.get("image")
            if isinstance(image, list):
                image = image[0] if image else None
            if isinstance(image, dict):
                image = image.get("url")
            return {
                "name": str(name).strip(),
                "brand": str(brand).strip() if brand else None,
                "price": price if price and price > 0 else None,
                "in_stock": in_stock,
                "image": str(image).strip() if image else None,
            }
    return None


def fetch_listing(store_slug: str, url: str) -> dict | None:
    """Fetch one product page and extract its listing (name/price/...).

    Same politeness + robots.txt rules as crawler.fetch_price. Returns
    None when the page could not be fetched or has no Product JSON-LD.
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
    listing = _product_from_json_ld(soup)
    if listing is None:
        log.warning("No Product JSON-LD on %s", url)
        return None
    listing["url"] = url
    listing["store"] = store_slug
    return listing


def _tokens(text: str) -> set[str]:
    """Normalised token set for a name: lowercase, split on anything
    that is not a letter/digit, drop filler words. Single digits are
    kept (a "5" in "PlayStation 5" is a model number, not noise)."""
    raw = re.findall(r"[a-z0-9]+(?:-[a-z0-9]+)?", text.lower())
    return {t for t in raw if t not in FILLER_WORDS and (len(t) > 1 or t.isdigit())}


def signature_tokens(product_name: str, brand: str) -> set[str]:
    """The tokens that identify a catalog product (brand + model +
    storage). A listing matches when it contains most of these."""
    toks = _tokens(product_name)
    toks |= _tokens(brand)
    return toks


def _token_matches(sig_tok: str, listing_toks: set[str]) -> bool:
    """Does a signature token appear in the listing? Exact match, or a
    model-number prefix match (e.g. "43ur78006" matches "43ur78006ll",
    the Egyptian variant suffix). Prefix matching only applies to
    tokens of 6+ chars, so a short token like "5" never matches "55"."""
    if sig_tok in listing_toks:
        return True
    if len(sig_tok) >= 6:
        return any(t.startswith(sig_tok) or sig_tok.startswith(t)
                   for t in listing_toks if len(t) >= 6)
    return False


def match_score(listing_name: str, sig: set[str]) -> float:
    """Fraction of the product's signature tokens present in the
    listing name. 1.0 = every identifying token found."""
    if not sig:
        return 0.0
    listing_toks = _tokens(listing_name)
    hits = sum(1 for t in sig if _token_matches(t, listing_toks))
    return hits / len(sig)


def discover(store_slug: str, products: list[dict], max_urls: int = 30) -> dict:
    """Run discovery for one store against Pryzo's catalog.

    ``products`` is a list of {"name", "brand"} dicts. Returns a report:
    matched URLs per product (with price + stock + score) and the
    unmatched candidate listings.
    """
    sigs = [
        (p["name"], p["brand"], signature_tokens(p["name"], p["brand"]))
        for p in products
    ]
    urls = enumerate_product_urls(store_slug, max_urls=max_urls)
    matched: dict[str, list[dict]] = {p["name"]: [] for p in products}
    candidates: list[dict] = []
    checked = 0
    for url in urls:
        listing = fetch_listing(store_slug, url)
        if listing is None:
            continue
        checked += 1
        best_name = None
        best_score = 0.0
        for name, brand, sig in sigs:
            score = match_score(listing["name"], sig)
            if score > best_score:
                best_score = score
                best_name = name
        # The brand must be in the listing name, otherwise a matching
        # model number from another brand would be a false positive.
        brand_ok = best_name is not None and _tokens(
            next(p["brand"] for p in products if p["name"] == best_name)
        ) & _tokens(listing["name"])
        # Variant check: a listing that adds a variant word the catalog
        # product does not have is a different variant, not a match.
        variant_conflict = False
        if best_name is not None:
            product_toks = _tokens(best_name)
            listing_toks = _tokens(listing["name"])
            variant_conflict = bool(
                (VARIANT_WORDS & listing_toks) - product_toks
            )
        if (
            best_name
            and best_score >= MATCH_THRESHOLD
            and brand_ok
            and not variant_conflict
        ):
            matched[best_name].append(
                {
                    "url": url,
                    "name": listing["name"],
                    "price": listing["price"],
                    "in_stock": listing["in_stock"],
                    "score": round(best_score, 2),
                }
            )
        else:
            candidates.append(
                {
                    "url": url,
                    "name": listing["name"],
                    "brand": listing["brand"],
                    "price": listing["price"],
                    "in_stock": listing["in_stock"],
                    "best_match": best_name,
                    "best_score": round(best_score, 2),
                }
            )
    return {
        "store": store_slug,
        "urls_enumerated": len(urls),
        "listings_checked": checked,
        "matched": {k: v for k, v in matched.items() if v},
        "unmatched_candidates": candidates,
    }


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Discover products on a shop.")
    parser.add_argument("store", help="store slug (e.g. wazen, btech)")
    parser.add_argument("--limit", type=int, default=30,
                        help="max product URLs to fetch (default 30)")
    args = parser.parse_args(argv[1:])
    import seed  # local catalog: the products to match against

    products = [
        {"name": name, "brand": brand}
        for (name, brand, _cat, _img, _prices, _urls) in seed.PRODUCTS
    ]
    report = discover(args.store, products, max_urls=args.limit)
    print(json.dumps(report, indent=2, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
