from contextlib import contextmanager

import paramiko

from app.config import get_settings


@contextmanager
def sftp_connection():
    s = get_settings()
    transport = paramiko.Transport((s.sftp_host, s.sftp_port))
    try:
        transport.connect(username=s.sftp_user, password=s.sftp_password)
        sftp = paramiko.SFTPClient.from_transport(transport)
        yield sftp
    finally:
        transport.close()
