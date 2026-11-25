"""One-off correction (2026-11-25): recompute ``PriceAlert.triggered``
from LIVE prices only.

Background: before ``PriceRecord.is_sample`` existed, the alert check in
``refresh.py`` used the lowest price across ALL records, so SAMPLE seed
prices could trigger alerts. The PS5 alert (target 40,000 EGP) was
triggered by the 32,999 EGP SAMPLE seed price while the live lowest was
50,000 EGP -- a false trigger. The alert flag is sticky by design (a
later price rise does not un-trigger it), so a normal refresh run cannot
undo that false trigger; this script does the correction once.

Rule (principled, not PS5-specific): an alert stays triggered only if
some LIVE price record for its product ever reached the target price
(``price <= target_price`` and ``is_sample = False``). Otherwise it is
reset to ``triggered = False``. A legitimately triggered alert -- one
whose target was really hit by a live price -- is untouched, even if
the price has since risen above target (stickiness preserved).

Run once::

    python recompute_alerts.py

Safe to re-run (idempotent: it recomputes the same value each time).
"""

from __future__ import annotations

from sqlalchemy import exists

from models import PriceAlert, PriceRecord, SessionLocal, init_db


def recompute_alerts() -> dict:
    init_db()
    db = SessionLocal()
    reset = kept = 0
    try:
        alerts = db.query(PriceAlert).all()
        for alert in alerts:
            hit_by_live = db.query(
                exists().where(
                    (PriceRecord.product_id == alert.product_id)
                    & (PriceRecord.is_sample.is_(False))
                    & (PriceRecord.price <= alert.target_price)
                )
            ).scalar()
            before = alert.triggered
            alert.triggered = bool(hit_by_live)
            if before and not alert.triggered:
                reset += 1
                print(
                    f"RESET alert id={alert.id} product_id={alert.product_id} "
                    f"target={alert.target_price}: no LIVE price ever hit "
                    f"the target (was triggered by a sample price)"
                )
            elif alert.triggered:
                kept += 1
        db.commit()
    finally:
        db.close()
    print(f"Recompute done: {reset} alert(s) reset, {kept} kept triggered")
    return {"reset": reset, "kept_triggered": kept}


if __name__ == "__main__":
    recompute_alerts()
