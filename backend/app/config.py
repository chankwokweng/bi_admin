from pydantic_settings import BaseSettings
from functools import lru_cache


class Settings(BaseSettings):
    # Database
    db_host: str
    db_port: int = 5432
    db_name: str
    db_user: str
    db_password: str

    # JWT
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expire_minutes: int = 15

    # SFTP
    sftp_host: str
    sftp_port: int = 22
    sftp_user: str
    sftp_password: str
    sftp_data_dir: str = "/data"
    sftp_logs_dir: str = "/logs"
    sftp_output_dir: str = "/output"

    # App
    cors_origins: str = "http://localhost,http://localhost:5000,http://localhost:80"

    class Config:
        env_file = ".env"
        case_sensitive = False


@lru_cache
def get_settings() -> Settings:
    return Settings()
