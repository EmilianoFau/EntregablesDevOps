from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    data_file: str = "/app/data/entries.json"
    app_version: str = "v1"
    deployment_color: str = "standalone"
    journal_timezone: str = "America/Montevideo"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")


@lru_cache
def get_settings() -> Settings:
    return Settings()
