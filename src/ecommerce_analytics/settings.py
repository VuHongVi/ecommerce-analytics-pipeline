import os
from dataclasses import dataclass, field
from pathlib import Path

from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_ENV_FILE = PROJECT_ROOT / ".env"


class SettingsError(ValueError):
    """Raised when application configuration is invalid."""


def _get_env(name: str, default: str = "", *, strip: bool = True) -> str:
    value = os.getenv(name, default)
    return value.strip() if strip else value


def _get_optional_path(name: str) -> Path | None:
    value = _get_env(name)
    return Path(value) if value else None


def _get_bool(name: str, default: bool) -> bool:
    raw_value = _get_env(name)

    if not raw_value:
        return default

    normalized_value = raw_value.lower()

    if normalized_value in {"1", "true", "yes", "on"}:
        return True

    if normalized_value in {"0", "false", "no", "off"}:
        return False

    raise SettingsError(f"{name} must be a boolean value.")


@dataclass(frozen=True, slots=True)
class Settings:
    app_env: str
    log_level: str
    business_timezone: str

    pancake_api_key: str = field(repr=False)

    meta_access_token: str = field(repr=False)
    meta_business_id: str
    meta_api_version: str

    private_data_root: Path | None
    private_output_root: Path | None
    private_work_root: Path | None

    sql_server: str
    sql_database: str
    sql_driver: str
    sql_auth_mode: str
    sql_username: str
    sql_password: str = field(repr=False)
    sql_encrypt: bool
    sql_trust_server_certificate: bool

    def require(self, *field_names: str) -> None:
        missing_fields = []

        for field_name in field_names:
            value = getattr(self, field_name)

            if value is None or (isinstance(value, str) and not value.strip()):
                missing_fields.append(field_name)

        if missing_fields:
            missing_list = ", ".join(missing_fields)
            raise SettingsError(f"Missing required settings: {missing_list}")


def load_settings(
    env_file: Path = DEFAULT_ENV_FILE,
) -> Settings:
    load_dotenv(dotenv_path=env_file, override=False)

    return Settings(
        app_env=_get_env("APP_ENV", "development"),
        log_level=_get_env("LOG_LEVEL", "INFO"),
        business_timezone=_get_env(
            "BUSINESS_TIMEZONE",
            "Asia/Ho_Chi_Minh",
        ),
        pancake_api_key=_get_env("PANCAKE_API_KEY"),
        meta_access_token=_get_env("META_ACCESS_TOKEN"),
        meta_business_id=_get_env("META_BUSINESS_ID"),
        meta_api_version=_get_env("META_API_VERSION", "v23.0"),
        private_data_root=_get_optional_path("PRIVATE_DATA_ROOT"),
        private_output_root=_get_optional_path("PRIVATE_OUTPUT_ROOT"),
        private_work_root=_get_optional_path("PRIVATE_WORK_ROOT"),
        sql_server=_get_env("SQL_SERVER"),
        sql_database=_get_env(
            "SQL_DATABASE",
            "ecommerce_analytics",
        ),
        sql_driver=_get_env(
            "SQL_DRIVER",
            "ODBC Driver 18 for SQL Server",
        ),
        sql_auth_mode=_get_env("SQL_AUTH_MODE", "windows"),
        sql_username=_get_env("SQL_USERNAME"),
        sql_password=_get_env(
            "SQL_PASSWORD",
            strip=False,
        ),
        sql_encrypt=_get_bool("SQL_ENCRYPT", True),
        sql_trust_server_certificate=_get_bool(
            "SQL_TRUST_SERVER_CERTIFICATE",
            True,
        ),
    )
