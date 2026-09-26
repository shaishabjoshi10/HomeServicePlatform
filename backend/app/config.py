from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    database_url: str
    jwt_secret: str
    jwt_algorithm: str = "HS256"
    jwt_expires_minutes: int = 10080  # 7 days
    allowed_origins: str = "*"

    # Local disk storage for provider verification documents (citizenship
    # photos). For a production deployment, swap this for cloud storage
    # (S3-compatible) and store URLs instead of local paths.
    upload_dir: str = "uploads"
    max_upload_mb: int = 5

    # The one Admin Dashboard account the app ships with — seeded into the
    # `admins` table at startup (see main._seed_default_admin) rather than
    # compared against directly, so the password is hashed at rest like
    # every other password in this app. Overridable via env vars
    # (ADMIN_EMAIL / ADMIN_PASSWORD) for a real deployment; these defaults
    # exist so the dashboard works out of the box.
    admin_email: str = "gharsewaadmin@gmail.com"
    admin_password: str = "gharsewanepal"

    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    @property
    def cors_origins(self) -> list[str]:
        if self.allowed_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]


settings = Settings()