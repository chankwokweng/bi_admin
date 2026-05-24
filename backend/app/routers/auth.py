from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from pydantic import BaseModel, EmailStr

from app.auth import verify_password, hash_password, create_access_token, decode_token
from app.database import get_pool
from app.dependencies import get_current_user

router = APIRouter(prefix="/auth", tags=["auth"])
bearer = HTTPBearer()


class LoginRequest(BaseModel):
    email: EmailStr
    password: str


class ChangePasswordRequest(BaseModel):
    current_password: str
    new_password: str


class TokenResponse(BaseModel):
    access_token: str
    token_type: str = "bearer"
    must_change_password: bool
    role: str


@router.post("/login", response_model=TokenResponse)
async def login(body: LoginRequest):
    pool = get_pool()
    row = await pool.fetchrow(
        "SELECT id, email, password_hash, role, is_approved, must_change_password FROM admin_users WHERE email = $1",
        body.email,
    )
    if not row or not verify_password(body.password, row["password_hash"]):
        raise HTTPException(status_code=status.HTTP_401_UNAUTHORIZED, detail="Invalid credentials")
    if not row["is_approved"]:
        raise HTTPException(status_code=status.HTTP_403_FORBIDDEN, detail="Account not approved")

    token = create_access_token({"sub": str(row["id"]), "role": row["role"]})
    return TokenResponse(
        access_token=token,
        must_change_password=row["must_change_password"],
        role=row["role"],
    )


@router.post("/refresh", response_model=TokenResponse)
async def refresh(user: dict = Depends(get_current_user)):
    """Extend session by issuing a fresh token. Called by frontend on user activity."""
    token = create_access_token({"sub": str(user["id"]), "role": user["role"]})
    return TokenResponse(
        access_token=token,
        must_change_password=user["must_change_password"],
        role=user["role"],
    )


@router.post("/change-password")
async def change_password(body: ChangePasswordRequest, user: dict = Depends(get_current_user)):
    pool = get_pool()
    row = await pool.fetchrow("SELECT password_hash FROM admin_users WHERE id = $1", user["id"])
    if not verify_password(body.current_password, row["password_hash"]):
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Current password is incorrect")
    if len(body.new_password) < 8:
        raise HTTPException(status_code=status.HTTP_400_BAD_REQUEST, detail="Password must be at least 8 characters")

    new_hash = hash_password(body.new_password)
    await pool.execute(
        "UPDATE admin_users SET password_hash = $1, must_change_password = FALSE, updated_at = NOW() WHERE id = $2",
        new_hash,
        user["id"],
    )
    return {"detail": "Password updated"}
