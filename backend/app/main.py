"""
FastAPI entry point for NutriLens backend.
"""

import os
from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

from app.routes.food_analysis import router as food_router
from app.routes.auth       import router as auth_router
from app.routes.users      import router as users_router
from app.routes.logs       import router as logs_router
from app.routes.barcode    import router as barcode_router
from app.routes.dashboard  import router as dashboard_router
from app.routes.grocery    import router as grocery_router
from app.database import init_db

load_dotenv()


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(
    title="NutriLens API",
    description="AI-powered dual-camera nutrition tracking",
    version="2.0.0",
    lifespan=lifespan,
)

# ── CORS ─────────────────────────────────────────────────────────────────────
allowed_origin = os.getenv("ALLOWED_ORIGIN", "http://localhost:5173")
allowed_origins = [allowed_origin, "http://localhost:5173"]
import re as _re
app.add_middleware(
    CORSMiddleware,
    allow_origin_regex=r"https?://(localhost|127\.0\.0\.1|192\.168\.\d+\.\d+|10\.\d+\.\d+\.\d+)(:\d+)?|https://.*\.trycloudflare\.com",
    allow_origins=allowed_origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Routes ────────────────────────────────────────────────────────────────────
app.include_router(food_router,      prefix="/api")
app.include_router(auth_router,      prefix="/api")
app.include_router(users_router,     prefix="/api")
app.include_router(logs_router,      prefix="/api")
app.include_router(barcode_router,   prefix="/api")
app.include_router(dashboard_router, prefix="/api")
app.include_router(grocery_router,   prefix="/api")


@app.get("/")
def health_check():
    return {"status": "ok", "message": "NutriLens API is running"}
