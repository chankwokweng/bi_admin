from fastapi import APIRouter, Depends, HTTPException, status
from pydantic import BaseModel, EmailStr

from app.auth import hash_password
from app.database import get_pool
from app.dependencies import require_super_admin
import secrets
import string

router = APIRouter(prefix="/users", tags=["users"])


def _generate_temp_password(length: int = 12) -> str:
    alphabet = string.ascii_letters + string.digits + "!@#$%"
    return "".join(secrets.choice(alphabet) for _ in range(length))


class CreateUserRequest(BaseModel):
    email: EmailStr
    role: str = "user"


class UpdateUserRequest(BaseModel):
    is_approved: bool | None = None
    role: str | None = None


class UserResponse(BaseModel):
    id: int
    email: str
    role: str
    is_approved: bool
    must_change_password: bool
    created_at: str


@router.get("", dependencies=[Depends(require_super_admin)])
async def list_users():
    pool = get_pool()
    rows = await pool.fetch(
        "SELECT id, email, role, is_approved, must_change_password, created_at FROM admin_users ORDER BY created_at DESC"
    )
    return [dict(r) for r in rows]


@router.post("", dependencies=[Depends(require_super_admin)])
async def create_user(body: CreateUserRequest):
    if body.role not in ("user", "super_admin"):
        raise HTTPException(status_code=400, detail="Role must be 'user' or 'super_admin'")

    pool = get_pool()
    existing = await pool.fetchval("SELECT id FROM admin_users WHERE email = $1", body.email)
    if existing:
        raise HTTPException(status_code=409, detail="Email already registered")

    temp_password = _generate_temp_password()
    pw_hash = hash_password(temp_password)

    row = await pool.fetchrow(
        """INSERT INTO admin_users (email, password_hash, role, is_approved, must_change_password)
           VALUES ($1, $2, $3, TRUE, TRUE)
           RETURNING id, email, role, is_approved, must_change_password, created_at""",
        body.email,
        pw_hash,
        body.role,
    )
    return {**dict(row), "temp_password": temp_password}


@router.put("/{user_id}", dependencies=[Depends(require_super_admin)])
async def update_user(user_id: int, body: UpdateUserRequest):
    pool = get_pool()
    row = await pool.fetchrow("SELECT id FROM admin_users WHERE id = $1", user_id)
    if not row:
        raise HTTPException(status_code=404, detail="User not found")

    updates = []
    values = []
    idx = 1
    if body.is_approved is not None:
        updates.append(f"is_approved = ${idx}")
        values.append(body.is_approved)
        idx += 1
    if body.role is not None:
        if body.role not in ("user", "super_admin"):
            raise HTTPException(status_code=400, detail="Invalid role")
        updates.append(f"role = ${idx}")
        values.append(body.role)
        idx += 1
    if not updates:
        raise HTTPException(status_code=400, detail="No fields to update")

    updates.append(f"updated_at = NOW()")
    values.append(user_id)
    await pool.execute(
        f"UPDATE admin_users SET {', '.join(updates)} WHERE id = ${idx}",
        *values,
    )
    return {"detail": "User updated"}


@router.post("/{user_id}/reset-password", dependencies=[Depends(require_super_admin)])
async def reset_password(user_id: int):
    pool = get_pool()
    row = await pool.fetchrow("SELECT id FROM admin_users WHERE id = $1", user_id)
    if not row:
        raise HTTPException(status_code=404, detail="User not found")

    temp_password = _generate_temp_password()
    pw_hash = hash_password(temp_password)
    await pool.execute(
        "UPDATE admin_users SET password_hash = $1, must_change_password = TRUE, updated_at = NOW() WHERE id = $2",
        pw_hash,
        user_id,
    )
    return {"temp_password": temp_password}


@router.delete("/{user_id}", dependencies=[Depends(require_super_admin)])
async def delete_user(user_id: int):
    pool = get_pool()
    result = await pool.execute("DELETE FROM admin_users WHERE id = $1", user_id)
    if result == "DELETE 0":
        raise HTTPException(status_code=404, detail="User not found")
    return {"detail": "User deleted"}
