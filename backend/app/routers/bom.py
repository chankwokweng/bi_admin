from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel
from decimal import Decimal

from app.database import get_pool
from app.dependencies import require_approved

router = APIRouter(prefix="/bom", tags=["bom"])


class BomRow(BaseModel):
    id: int
    usage_sku_code: str | None
    raw_product: str
    raw_product_sku_code: str | None
    cost: Decimal | None
    uom: str | None
    unit_qty_in_uom: Decimal | None
    bom_qty_in_uom: Decimal | None
    bom_cost: Decimal | None
    bom_qty_in_unit: Decimal | None
    raw_product_sort_seq: int | None
    # joined from products
    product_name: str | None
    product_category: str | None


class BomWithProduct(BaseModel):
    product_id: int | None
    product_name: str | None
    product_sku_code: str
    product_category: str | None
    bom_rows: list[BomRow]


class CreateBomRequest(BaseModel):
    usage_sku_code: str
    raw_product: str
    raw_product_sku_code: str | None = None
    cost: Decimal | None = None
    uom: str | None = None
    unit_qty_in_uom: Decimal | None = None
    bom_qty_in_uom: Decimal | None = None
    bom_cost: Decimal | None = None
    bom_qty_in_unit: Decimal | None = None
    raw_product_sort_seq: int | None = None


class UpdateBomRequest(BaseModel):
    raw_product: str | None = None
    raw_product_sku_code: str | None = None
    cost: Decimal | None = None
    uom: str | None = None
    unit_qty_in_uom: Decimal | None = None
    bom_qty_in_uom: Decimal | None = None
    bom_cost: Decimal | None = None
    bom_qty_in_unit: Decimal | None = None
    raw_product_sort_seq: int | None = None

    model_config = {"extra": "forbid"}


class BomListResponse(BaseModel):
    items: list[BomWithProduct]
    total: int


@router.get("", response_model=BomListResponse)
async def list_bom(
    search: str = Query("", description="Search product name or sku_code"),
    category: str = Query("", description="Filter by product category"),
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=200),
    _user=Depends(require_approved),
):
    pool = get_pool()
    conditions = []
    values = []
    idx = 1

    if search:
        conditions.append(f"(p.name ILIKE ${idx} OR p.sku_code ILIKE ${idx})")
        values.append(f"%{search}%")
        idx += 1
    if category:
        conditions.append(f"p.category = ${idx}")
        values.append(category)
        idx += 1

    where = f"WHERE {' AND '.join(conditions)}" if conditions else ""

    # Count distinct products that have BOM entries
    count_row = await pool.fetchrow(
        f"""SELECT COUNT(DISTINCT p.sku_code)
            FROM products p
            INNER JOIN bom b ON p.sku_code = b.usage_sku_code
            {where}""",
        *values,
    )
    total = count_row["count"]

    offset = (page - 1) * page_size
    rows = await pool.fetch(
        f"""SELECT b.id, b.usage_sku_code, b.raw_product, b.raw_product_sku_code,
                   b.cost, b.uom, b.unit_qty_in_uom, b.bom_qty_in_uom,
                   b.bom_cost, b.bom_qty_in_unit, b.raw_product_sort_seq,
                   p.id AS product_id, p.name AS product_name, p.category AS product_category
            FROM products p
            INNER JOIN bom b ON p.sku_code = b.usage_sku_code
            {where}
            ORDER BY p.name, b.raw_product_sort_seq NULLS LAST, b.raw_product
            LIMIT ${idx} OFFSET ${idx + 1}""",
        *values,
        page_size * 10,  # fetch more rows to group
        offset * 10,
    )

    # Group by product sku
    product_map: dict[str, BomWithProduct] = {}
    for r in rows:
        sku = r["usage_sku_code"]
        if sku not in product_map:
            product_map[sku] = BomWithProduct(
                product_id=r["product_id"],
                product_name=r["product_name"],
                product_sku_code=sku,
                product_category=r["product_category"],
                bom_rows=[],
            )
        product_map[sku].bom_rows.append(BomRow(**dict(r)))

    return BomListResponse(items=list(product_map.values()), total=total)


@router.get("/{sku_code}", response_model=BomWithProduct)
async def get_bom_for_product(sku_code: str, _user=Depends(require_approved)):
    pool = get_pool()
    product = await pool.fetchrow(
        "SELECT id, name, sku_code, category FROM products WHERE sku_code = $1", sku_code
    )
    if not product:
        raise HTTPException(status_code=404, detail="Product not found")

    rows = await pool.fetch(
        """SELECT b.id, b.usage_sku_code, b.raw_product, b.raw_product_sku_code,
                  b.cost, b.uom, b.unit_qty_in_uom, b.bom_qty_in_uom,
                  b.bom_cost, b.bom_qty_in_unit, b.raw_product_sort_seq,
                  p.id AS product_id, p.name AS product_name, p.category AS product_category
           FROM bom b
           LEFT JOIN products p ON b.usage_sku_code = p.sku_code
           WHERE b.usage_sku_code = $1
           ORDER BY b.raw_product_sort_seq NULLS LAST, b.raw_product""",
        sku_code,
    )
    return BomWithProduct(
        product_id=product["id"],
        product_name=product["name"],
        product_sku_code=sku_code,
        product_category=product["category"],
        bom_rows=[BomRow(**dict(r)) for r in rows],
    )


@router.post("", response_model=BomRow, status_code=201)
async def create_bom_row(body: CreateBomRequest, _user=Depends(require_approved)):
    pool = get_pool()
    product = await pool.fetchrow("SELECT id FROM products WHERE sku_code = $1", body.usage_sku_code)
    if not product:
        raise HTTPException(status_code=404, detail="Product SKU not found")

    row = await pool.fetchrow(
        """INSERT INTO bom (usage_sku_code, raw_product, raw_product_sku_code, cost, uom,
                            unit_qty_in_uom, bom_qty_in_uom, bom_cost, bom_qty_in_unit, raw_product_sort_seq)
           VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10)
           RETURNING id, usage_sku_code, raw_product, raw_product_sku_code, cost, uom,
                     unit_qty_in_uom, bom_qty_in_uom, bom_cost, bom_qty_in_unit, raw_product_sort_seq""",
        body.usage_sku_code, body.raw_product, body.raw_product_sku_code, body.cost,
        body.uom, body.unit_qty_in_uom, body.bom_qty_in_uom, body.bom_cost,
        body.bom_qty_in_unit, body.raw_product_sort_seq,
    )
    return {**dict(row), "product_name": None, "product_category": None}


@router.put("/{bom_id}", response_model=BomRow)
async def update_bom_row(bom_id: int, body: UpdateBomRequest, _user=Depends(require_approved)):
    pool = get_pool()
    existing = await pool.fetchrow("SELECT id FROM bom WHERE id = $1", bom_id)
    if not existing:
        raise HTTPException(status_code=404, detail="BOM row not found")

    editable = ["raw_product", "raw_product_sku_code", "cost", "uom",
                "unit_qty_in_uom", "bom_qty_in_uom", "bom_cost", "bom_qty_in_unit", "raw_product_sort_seq"]
    updates = []
    values = []
    idx = 1
    for field in editable:
        val = getattr(body, field)
        if val is not None:
            updates.append(f"{field} = ${idx}")
            values.append(val)
            idx += 1

    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    values.append(bom_id)
    updated = await pool.fetchrow(
        f"""UPDATE bom SET {', '.join(updates)} WHERE id = ${idx}
            RETURNING id, usage_sku_code, raw_product, raw_product_sku_code, cost, uom,
                      unit_qty_in_uom, bom_qty_in_uom, bom_cost, bom_qty_in_unit, raw_product_sort_seq""",
        *values,
    )
    return {**dict(updated), "product_name": None, "product_category": None}


@router.delete("/{bom_id}")
async def delete_bom_row(bom_id: int, _user=Depends(require_approved)):
    pool = get_pool()
    result = await pool.execute("DELETE FROM bom WHERE id = $1", bom_id)
    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="BOM row not found")
    return {"detail": "BOM row deleted"}
