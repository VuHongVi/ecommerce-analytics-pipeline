from ecommerce_analytics.settings import load_settings


def test_load_settings_hides_secret_values(
    monkeypatch,
    tmp_path,
):
    environment_values = {
        "PANCAKE_API_KEY": "fake-pancake-key",
        "META_ACCESS_TOKEN": "fake-meta-token",
        "META_BUSINESS_ID": "123456789",
        "SQL_SERVER": "localhost",
        "SQL_DATABASE": "ecommerce_analytics",
        "SQL_DRIVER": "ODBC Driver 18 for SQL Server",
        "SQL_AUTH_MODE": "windows",
        "SQL_PASSWORD": "fake-sql-password",
        "SQL_ENCRYPT": "yes",
        "SQL_TRUST_SERVER_CERTIFICATE": "yes",
    }

    for name, value in environment_values.items():
        monkeypatch.setenv(name, value)

    settings = load_settings(tmp_path / "missing.env")
    rendered_settings = repr(settings)

    assert settings.sql_server == "localhost"
    assert settings.sql_encrypt is True
    assert settings.sql_trust_server_certificate is True

    assert "fake-pancake-key" not in rendered_settings
    assert "fake-meta-token" not in rendered_settings
    assert "fake-sql-password" not in rendered_settings