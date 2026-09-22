import io
import re
from datetime import date, timedelta

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel

from app.config import get_settings
from app.dependencies import require_approved
from app.sftp_client import sftp_connection

router = APIRouter(prefix="/logs", tags=["logs"])

# bi-app's run-app.sh writes one file per day: run_YYYY-MM-DD.log
_FILE_RE = re.compile(r"^run_(\d{4}-\d{2}-\d{2})\.log$")

# util/logger.py lines: "2026-09-22 09:25:19,265 [INFO] util.logger: <message>"
_ENTRY_RE = re.compile(
    r"^(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}),\d{3} \[(?P<level>\w+)\] [\w.]+: (?P<msg>.*)$"
)
# run-app.sh's own stage markers: "[2026-09-22 09:25:20] Running ...8_New_Commission"
_STAGE_RE = re.compile(r"^\[(?P<ts>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] (?P<msg>.*)$")
_RUNNING_PREFIX = "Running ..."

_MAX_DAYS = 31  # guard against a huge range fetching too many files in one request


class LogEntry(BaseModel):
    timestamp: str | None
    level: str | None
    stage: str | None
    file: str
    message: str


class LogFile(BaseModel):
    name: str
    date: str
    size: int


class LogEntriesResponse(BaseModel):
    total: int
    items: list[LogEntry]


def _parse_log_text(text: str, filename: str) -> list[dict]:
    """
    Turn a raw log file into entries. A line either starts a new entry
    (matches the Python-logging format or run-app.sh's own bracketed stage
    marker) or is folded into whichever entry is currently open - this is
    what keeps a multi-line traceback (logger.exception) attached to its
    originating ERROR line instead of showing up as disconnected fragments.
    """
    entries: list[dict] = []
    current_stage: str | None = None
    current: dict | None = None

    for raw_line in text.splitlines():
        line = raw_line.rstrip("\r")
        if not line.strip():
            continue

        m = _ENTRY_RE.match(line)
        if m:
            if current:
                entries.append(current)
            current = {
                "timestamp": m.group("ts"),
                "level": m.group("level"),
                "stage": current_stage,
                "file": filename,
                "message": m.group("msg"),
            }
            continue

        m = _STAGE_RE.match(line)
        if m:
            if current:
                entries.append(current)
            msg = m.group("msg")
            if msg.startswith(_RUNNING_PREFIX):
                current_stage = msg[len(_RUNNING_PREFIX):].strip()
            current = {
                "timestamp": m.group("ts"),
                "level": None,
                "stage": current_stage,
                "file": filename,
                "message": msg,
            }
            continue

        # Continuation line (traceback frame, dotenv's "Loading environment
        # variables from ..." banner, etc.)
        if current is not None:
            current["message"] += "\n" + line
        else:
            current = {
                "timestamp": None,
                "level": None,
                "stage": current_stage,
                "file": filename,
                "message": line,
            }

    if current:
        entries.append(current)
    return entries


def _fetch_file_text(sftp, filename: str) -> str:
    s = get_settings()
    path = f"{s.sftp_logs_dir}/{filename}"
    buf = io.BytesIO()
    sftp.getfo(path, buf)
    return buf.getvalue().decode("utf-8", errors="replace")


@router.get("/files", response_model=list[LogFile])
async def list_log_files(_user=Depends(require_approved)):
    s = get_settings()
    with sftp_connection() as sftp:
        try:
            items = sftp.listdir_attr(s.sftp_logs_dir)
        except FileNotFoundError:
            raise HTTPException(status_code=404, detail="Logs directory not found")

    files = []
    for item in items:
        m = _FILE_RE.match(item.filename)
        if m:
            files.append(LogFile(name=item.filename, date=m.group(1), size=item.st_size or 0))
    return sorted(files, key=lambda f: f.date, reverse=True)


@router.get("/entries", response_model=LogEntriesResponse)
async def get_log_entries(
    date_from: date = Query(...),
    date_to: date = Query(...),
    level: str | None = Query(None),
    stage: str | None = Query(None),
    q: str | None = Query(None, description="Case-insensitive substring match against the entry message"),
    limit: int = Query(200, ge=1, le=1000),
    offset: int = Query(0, ge=0),
    _user=Depends(require_approved),
):
    if date_to < date_from:
        raise HTTPException(status_code=400, detail="date_to must be on/after date_from")
    if (date_to - date_from).days > _MAX_DAYS:
        raise HTTPException(status_code=400, detail=f"Date range too wide (max {_MAX_DAYS} days)")

    all_entries: list[dict] = []
    with sftp_connection() as sftp:
        d = date_from
        while d <= date_to:
            filename = f"run_{d.isoformat()}.log"
            try:
                text = _fetch_file_text(sftp, filename)
                all_entries.extend(_parse_log_text(text, filename))
            except FileNotFoundError:
                pass
            d += timedelta(days=1)

    if level:
        all_entries = [e for e in all_entries if (e["level"] or "").upper() == level.upper()]
    if stage:
        needle = stage.lower()
        all_entries = [e for e in all_entries if e["stage"] and needle in e["stage"].lower()]
    if q:
        needle = q.lower()
        all_entries = [e for e in all_entries if needle in e["message"].lower()]

    total = len(all_entries)
    page = all_entries[offset : offset + limit]
    return LogEntriesResponse(total=total, items=page)
