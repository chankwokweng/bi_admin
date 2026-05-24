import io
import os
import stat
import zipfile
from contextlib import contextmanager
from datetime import datetime
from typing import Literal

import paramiko
from fastapi import APIRouter, Depends, HTTPException, UploadFile, File, Query
from fastapi.responses import StreamingResponse
from pydantic import BaseModel

from app.config import get_settings
from app.dependencies import require_approved

router = APIRouter(prefix="/sftp", tags=["sftp"])

# Allowed root directories and their write/delete permissions
_DIRS = {
    "data": {"write": True, "delete": True},
    "logs": {"write": False, "delete": True},
    "output": {"write": False, "delete": True},
}


@contextmanager
def _sftp_connection():
    s = get_settings()
    transport = paramiko.Transport((s.sftp_host, s.sftp_port))
    try:
        transport.connect(username=s.sftp_user, password=s.sftp_password)
        sftp = paramiko.SFTPClient.from_transport(transport)
        yield sftp
    finally:
        transport.close()


def _resolve_path(root: str, subpath: str) -> str:
    """Resolve a safe absolute path under root, preventing path traversal."""
    s = get_settings()
    root_map = {
        "data": s.sftp_data_dir,
        "logs": s.sftp_logs_dir,
        "output": s.sftp_output_dir,
    }
    base = root_map[root]
    # Normalise and strip leading slash from subpath
    clean = os.path.normpath(subpath or "/").lstrip("/")
    full = base if not clean or clean == "." else f"{base}/{clean}"
    # Safety check: resolved path must stay within base
    if not full.startswith(base):
        raise HTTPException(status_code=400, detail="Invalid path")
    return full


class FileItem(BaseModel):
    name: str
    is_dir: bool
    size: int
    modified: str


@router.get("/list", response_model=list[FileItem])
async def list_directory(
    root: Literal["data", "logs", "output"],
    subpath: str = "",
    _user=Depends(require_approved),
):
    path = _resolve_path(root, subpath)
    with _sftp_connection() as sftp:
        try:
            items = sftp.listdir_attr(path)
        except FileNotFoundError:
            raise HTTPException(status_code=404, detail="Directory not found")
        result = []
        for item in items:
            result.append(
                FileItem(
                    name=item.filename,
                    is_dir=stat.S_ISDIR(item.st_mode),
                    size=item.st_size or 0,
                    modified=datetime.fromtimestamp(item.st_mtime).isoformat() if item.st_mtime else "",
                )
            )
    return sorted(result, key=lambda x: (not x.is_dir, x.name))


@router.get("/download")
async def download_file(
    root: Literal["data", "logs", "output"],
    subpath: str,
    _user=Depends(require_approved),
):
    path = _resolve_path(root, subpath)
    filename = os.path.basename(path)

    def _stream():
        with _sftp_connection() as sftp:
            buf = io.BytesIO()
            sftp.getfo(path, buf)
            buf.seek(0)
            yield from iter(lambda: buf.read(65536), b"")

    return StreamingResponse(
        _stream(),
        media_type="application/octet-stream",
        headers={"Content-Disposition": f'attachment; filename="{filename}"'},
    )


@router.post("/upload")
async def upload_file(
    root: Literal["data"] = Query(...),
    subpath: str = Query(""),
    file: UploadFile = File(...),
    _user=Depends(require_approved),
):
    if not _DIRS[root]["write"]:
        raise HTTPException(status_code=403, detail=f"Uploads not allowed in '{root}'")

    dir_path = _resolve_path(root, subpath)
    file_path = f"{dir_path}/{file.filename}"

    content = await file.read()
    with _sftp_connection() as sftp:
        try:
            sftp.stat(dir_path)
        except FileNotFoundError:
            sftp.mkdir(dir_path)
        with sftp.open(file_path, "wb") as remote_file:
            remote_file.write(content)

    return {"detail": f"Uploaded {file.filename}"}


@router.delete("/delete")
async def delete_file(
    root: Literal["data", "logs", "output"],
    subpath: str,
    _user=Depends(require_approved),
):
    if not _DIRS[root]["delete"]:
        raise HTTPException(status_code=403, detail=f"Delete not allowed in '{root}'")

    path = _resolve_path(root, subpath)
    with _sftp_connection() as sftp:
        try:
            attr = sftp.stat(path)
        except FileNotFoundError:
            raise HTTPException(status_code=404, detail="File not found")
        if stat.S_ISDIR(attr.st_mode):
            raise HTTPException(status_code=400, detail="Path is a directory; only files can be deleted")
        sftp.remove(path)

    return {"detail": "File deleted"}


@router.post("/archive")
async def archive_file(
    root: Literal["logs", "output"],
    subpath: str,
    _user=Depends(require_approved),
):
    """Compress a file to _archive/<filename>.zip in the same root dir, then delete the original."""
    path = _resolve_path(root, subpath)
    filename = os.path.basename(path)
    parent_dir = os.path.dirname(path)

    s = get_settings()
    root_map = {"logs": s.sftp_logs_dir, "output": s.sftp_output_dir}
    archive_dir = f"{root_map[root]}/_archive"
    zip_name = f"{filename}.zip"
    zip_path = f"{archive_dir}/{zip_name}"

    with _sftp_connection() as sftp:
        # Ensure _archive dir exists
        try:
            sftp.stat(archive_dir)
        except FileNotFoundError:
            sftp.mkdir(archive_dir)

        # Read original file
        buf = io.BytesIO()
        try:
            sftp.getfo(path, buf)
        except FileNotFoundError:
            raise HTTPException(status_code=404, detail="File not found")

        # Create zip in memory
        zip_buf = io.BytesIO()
        with zipfile.ZipFile(zip_buf, "w", zipfile.ZIP_DEFLATED) as zf:
            buf.seek(0)
            zf.writestr(filename, buf.read())
        zip_buf.seek(0)

        # Upload zip
        with sftp.open(zip_path, "wb") as zf:
            zf.write(zip_buf.read())

        # Delete original
        sftp.remove(path)

    return {"detail": f"Archived to _archive/{zip_name}"}
