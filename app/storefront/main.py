"""storefront-service — frontend que llama a payments en cada checkout.

Expone /checkout, que invoca a payments:/charge. Si payments falla, el error se
propaga y Dynatrace/Davis lo ve como una falla distribuida entre dos servicios.
"""
import os

import httpx
from fastapi import FastAPI, HTTPException

app = FastAPI(title="storefront-service")

PAYMENTS_URL = os.getenv("PAYMENTS_URL", "http://payments:8080")
VERSION = os.getenv("APP_VERSION", "v1")


@app.get("/healthz")
def healthz():
    return {"status": "ok", "version": VERSION}


@app.get("/checkout")
def checkout():
    try:
        r = httpx.post(f"{PAYMENTS_URL}/charge", timeout=5.0)
        r.raise_for_status()
    except Exception as e:  # noqa: BLE001
        raise HTTPException(status_code=502, detail=f"checkout failed: {e}")
    return {"status": "ok", "payment": r.json()}
