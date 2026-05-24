from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from datetime import date

from app.database import get_pool
from app.dependencies import require_approved

router = APIRouter(prefix="/cutoff", tags=["cutoff"])


class CutoffPeriod(BaseModel):
    type: str
    last_processed_date: date | None
    cutoff_date: date | None
    flag_dryrun: int


class UpdateCutoffRequest(BaseModel):
    last_processed_date: date | None = None
    cutoff_date: date | None = None
    flag_dryrun: int | None = None

    model_config = {"extra": "forbid"}


@router.get("", response_model=list[CutoffPeriod])
async def list_cutoff(_user=Depends(require_approved)):
    pool = get_pool()
    rows = await pool.fetch("SELECT type, last_processed_date, cutoff_date, flag_dryrun FROM cutoff_period ORDER BY type")
    return [dict(r) for r in rows]


@router.put("/{type_key}", response_model=CutoffPeriod)
async def update_cutoff(type_key: str, body: UpdateCutoffRequest, _user=Depends(require_approved)):
    pool = get_pool()
    row = await pool.fetchrow("SELECT type FROM cutoff_period WHERE type = $1", type_key)
    if not row:
        raise HTTPException(status_code=404, detail="Cutoff period not found")

    updates = []
    values = []
    idx = 1
    if body.last_processed_date is not None:
        updates.append(f"last_processed_date = ${idx}")
        values.append(body.last_processed_date)
        idx += 1
    if body.cutoff_date is not None:
        updates.append(f"cutoff_date = ${idx}")
        values.append(body.cutoff_date)
        idx += 1
    if body.flag_dryrun is not None:
        if body.flag_dryrun not in (0, 1):
            raise HTTPException(status_code=400, detail="flag_dryrun must be 0 or 1")
        updates.append(f"flag_dryrun = ${idx}")
        values.append(body.flag_dryrun)
        idx += 1
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    values.append(type_key)
    updated = await pool.fetchrow(
        f"UPDATE cutoff_period SET {', '.join(updates)} WHERE type = ${idx} RETURNING type, last_processed_date, cutoff_date, flag_dryrun",
        *values,
    )
    return dict(updated)
