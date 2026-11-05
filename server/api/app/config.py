"""小食痰记同步服务：配置。"""

import os
from dataclasses import dataclass, field


def _int(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    return int(raw)


@dataclass(frozen=True)
class Settings:
    """全部可被环境变量覆盖，便于同一份镜像在测试与生产间切换。"""

    database_url: str = field(
        default_factory=lambda: os.environ.get(
            "DATABASE_URL", "sqlite+aiosqlite:///./diary-sync.db"
        )
    )
    token_ttl_days: int = field(default_factory=lambda: _int("TOKEN_TTL_DAYS", 30))
    max_payload_bytes: int = field(default_factory=lambda: _int("MAX_PAYLOAD_BYTES", 8 * 1024 * 1024))
    versions_kept: int = field(default_factory=lambda: _int("VERSIONS_KEPT", 20))
    max_users: int = field(default_factory=lambda: _int("MAX_USERS", 50))
    auth_attempts_per_minute: int = field(default_factory=lambda: _int("AUTH_ATTEMPTS_PER_MINUTE", 10))
    trust_proxy_headers: bool = field(
        default_factory=lambda: os.environ.get("TRUST_PROXY_HEADERS", "1") == "1"
    )
    ai_api_key: str = field(default_factory=lambda: os.environ.get("DEEPSEEK_API_KEY", "").strip())
    ai_model: str = field(default_factory=lambda: os.environ.get("DEEPSEEK_MODEL", "deepseek-flash"))
    ai_daily_limit: int = field(default_factory=lambda: _int("AI_DAILY_LIMIT", 60))
    ai_global_daily_limit: int = field(default_factory=lambda: _int("AI_GLOBAL_DAILY_LIMIT", 1000))
    ai_requests_per_minute: int = field(default_factory=lambda: _int("AI_REQUESTS_PER_MINUTE", 10))
    ai_max_concurrent: int = field(default_factory=lambda: _int("AI_MAX_CONCURRENT", 4))


settings = Settings()
