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

    # eSewa ePay v2. Keep the secret only on the FastAPI server.
    esewa_environment: str = "uat"
    esewa_product_code: str = "EPAYTEST"
    esewa_secret_key: str = "8gBm/:&EnhH.1/q("
    # Must be a public HTTPS URL in UAT/production so eSewa can redirect
    # back to the merchant. For local development use a tunnel such as ngrok.
    esewa_public_base_url: str = "https://crayon-critter-dentist.ngrok-free.dev"
    esewa_signed_field_names: str = "total_amount,transaction_uuid,product_code"

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
    def esewa_form_url(self) -> str:
        if self.esewa_environment.lower() in {"live", "production"}:
            return "https://epay.esewa.com.np/api/epay/main/v2/form"
        return "https://rc-epay.esewa.com.np/api/epay/main/v2/form"

    @property
    def esewa_status_urls(self) -> list[str]:
        """Status-check endpoints to try, in order.

        eSewa's docs have listed several hosts for the test environment over
        time, so try each until one answers.
        """
        if self.esewa_environment.lower() in {"live", "production"}:
            return [
                "https://epay.esewa.com.np/api/epay/transaction/status/",
                "https://esewa.com.np/api/epay/transaction/status/",
            ]
        return [
            "https://rc.esewa.com.np/api/epay/transaction/status/",
            "https://rc-epay.esewa.com.np/api/epay/transaction/status/",
            "https://uat.esewa.com.np/api/epay/transaction/status/",
        ]

    @property
    def cors_origins(self) -> list[str]:
        if self.allowed_origins.strip() == "*":
            return ["*"]
        return [o.strip() for o in self.allowed_origins.split(",") if o.strip()]


settings = Settings()