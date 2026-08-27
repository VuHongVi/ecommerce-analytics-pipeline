import pyodbc

from ecommerce_analytics.settings import Settings, SettingsError


def _yes_no(value: bool) -> str:
    return "yes" if value else "no"


def build_connection_string(
    settings: Settings,
    database: str | None = None,
) -> str:
    settings.require(
        "sql_server",
        "sql_driver",
        "sql_auth_mode",
    )

    target_database = database or settings.sql_database

    if not target_database:
        raise SettingsError("SQL database is required.")

    connection_parts = [
        f"DRIVER={{{settings.sql_driver}}}",
        f"SERVER={settings.sql_server}",
        f"DATABASE={target_database}",
        f"Encrypt={_yes_no(settings.sql_encrypt)}",
        (
            "TrustServerCertificate="
            f"{_yes_no(settings.sql_trust_server_certificate)}"
        ),
    ]

    auth_mode = settings.sql_auth_mode.lower()

    if auth_mode == "windows":
        connection_parts.append("Trusted_Connection=yes")
    elif auth_mode == "sql":
        settings.require("sql_username", "sql_password")
        connection_parts.extend(
            [
                f"UID={settings.sql_username}",
                f"PWD={settings.sql_password}",
            ]
        )
    else:
        raise SettingsError(
            "SQL_AUTH_MODE must be 'windows' or 'sql'."
        )

    return ";".join(connection_parts)


def connect_sql_server(
    settings: Settings,
    database: str | None = None,
    *,
    timeout: int = 30,
    autocommit: bool = False,
) -> pyodbc.Connection:
    connection_string = build_connection_string(
        settings=settings,
        database=database,
    )

    return pyodbc.connect(
        connection_string,
        timeout=timeout,
        autocommit=autocommit,
    )