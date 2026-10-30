"""payments-service — microservicio con falla inyectable por configuración.

La probabilidad de fallo y la latencia extra se controlan por variables de
entorno (definidas en el manifiesto de K8s), para que la REMEDIACIÓN sea editar
el manifiesto y abrir un PR.

  FAIL_RATE   prob. de responder 500 (0.0–1.0).  "bad deploy" = 0.4
  SLOW_MS     latencia extra en ms por request (0 = normal)
"""
import os
import random
import time

from fastapi import FastAPI, HTTPException

app = FastAPI(title="payments-service")

FAIL_RATE = float(os.getenv("FAIL_RATE", "0.0"))
SLOW_MS = int(os.getenv("SLOW_MS", "0"))
VERSION = os.getenv("APP_VERSION", "v1")


@app.get("/healthz")
def healthz():
    return {"status": "ok", "version": VERSION}


@app.post("/charge")
@app.get("/charge")
def charge():
    if SLOW_MS:
        time.sleep(SLOW_MS / 1000.0)
    if random.random() < FAIL_RATE:
        # Falla simulada: gateway de pagos caído
        raise HTTPException(status_code=500, detail="payment gateway error")
    return {"status": "charged", "version": VERSION}
