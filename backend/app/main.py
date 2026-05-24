from contextlib import asynccontextmanager
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.config import get_settings
from app.database import create_pool, close_pool
from app.routers import auth, users, sftp, cutoff, products, bom


@asynccontextmanager
async def lifespan(app: FastAPI):
    await create_pool()
    yield
    await close_pool()


app = FastAPI(title="BI Admin API", version="1.0.0", lifespan=lifespan)

s = get_settings()
origins = [o.strip() for o in s.cors_origins.split(",")]
print(f"[CORS] Allowed origins: {origins}")
app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth.router)
app.include_router(users.router)
app.include_router(sftp.router)
app.include_router(cutoff.router)
app.include_router(products.router)
app.include_router(bom.router)


@app.get("/health")
async def health():
    return {"status": "ok"}
