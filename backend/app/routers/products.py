from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from datetime import datetime
from decimal import Decimal

from app.database import get_pool
from app.dependencies import require_approved

router = APIRouter(prefix="/products", tags=["products"])


class Product(BaseModel):
    id: int
    name: str
    sku_code: str | None
    category: str | None
    subcategory: str | None
    selling_price: Decimal | None
    cost_price: Decimal | None
    translated_sku_code: str | None
    translated_category: str | None
    created_at: datetime | None
    updated_at: datetime | None


class UpdateProductRequest(BaseModel):
    category: str | None = None
    subcategory: str | None = None
    selling_price: Decimal | None = None
    cost_price: Decimal | None = None
    translated_sku_code: str | None = None
    translated_category: str | None = None

    model_config = {"extra": "forbid"}


class ProductListResponse(BaseModel):
    items: list[Product]
    total: int


@router.get("", response_model=ProductListResponse)
async def list_products(
    search: str = Query("", description="Search name or sku_code"),
    category: str = Query("", description="Filter by category"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    _user=Depends(require_approved),
):
    pool = get_pool()
    conditions = []
    values = []
    idx = 1

    if search:
        conditions.append(f"(name ILIKE ${idx} OR sku_code ILIKE ${idx})")
        values.append(f"%{search}%")
        idx += 1
    if category:
        conditions.append(f"category = ${idx}")
        values.append(category)
        idx += 1

    where = f"WHERE {' AND '.join(conditions)}" if conditions else ""
    offset = (page - 1) * page_size

    count_row = await pool.fetchrow(f"SELECT COUNT(*) FROM products {where}", *values)
    total = count_row["count"]

    rows = await pool.fetch(
        f"""SELECT id, name, sku_code, category, subcategory, selling_price, cost_price,
                   translated_sku_code, translated_category, created_at, updated_at
            FROM products {where}
            ORDER BY name
            LIMIT ${idx} OFFSET ${idx + 1}""",
        *values,
        page_size,
        offset,
    )
    return ProductListResponse(items=[dict(r) for r in rows], total=total)


@router.get("/categories")
async def list_categories(_user=Depends(require_approved)):
    pool = get_pool()
    rows = await pool.fetch("SELECT DISTINCT category FROM products WHERE category IS NOT NULL ORDER BY category")
    return [r["category"] for r in rows]


@router.put("/{product_id}", response_model=Product)
async def update_product(product_id: int, body: UpdateProductRequest, _user=Depends(require_approved)):
    pool = get_pool()
    row = await pool.fetchrow("SELECT id FROM products WHERE id = $1", product_id)
    if not row:
        raise HTTPException(status_code=404, detail="Product not found")

    updates = []
    values = []
    idx = 1
    for field in ("category", "subcategory", "selling_price", "cost_price", "translated_sku_code", "translated_category"):
        val = getattr(body, field)
        if val is not None:
            updates.append(f"{field} = ${idx}")
            values.append(val)
            idx += 1

    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    updates.append(f"updated_at = NOW()")
    values.append(product_id)
    updated = await pool.fetchrow(
        f"""UPDATE products SET {', '.join(updates)} WHERE id = ${idx}
            RETURNING id, name, sku_code, category, subcategory, selling_price, cost_price,
                      translated_sku_code, translated_category, created_at, updated_at""",
        *values,
    )
    return dict(updated)
