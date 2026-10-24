"""Runtime configuration; never persist passwords or DSNs in source control."""

from __future__ import annotations

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Config:
    db_host: str = "127.0.0.1"
    db_port: int = 5432
    db_name: str = "kilos_grammar"
    db_user: str = "postgres"
    db_password: str = ""
    http_port: int = 18765

    @classmethod
    def from_env(cls) -> Config:
        host = os.getenv("KILOS_DB_HOST", "127.0.0.1").strip().lower()
        if host not in {"127.0.0.1", "localhost", "::1"}:
            raise ValueError("KILOS_DB_HOST must be a local loopback hostname/address")
        db_port = int(os.getenv("KILOS_DB_PORT", "5432"))
        http_port = int(os.getenv("KILOS_HTTP_PORT", "18765"))
        if not 1 <= db_port <= 65535 or not 1 <= http_port <= 65535:
            raise ValueError("Database and HTTP ports must be in the range 1-65535")
        db_name = os.getenv("KILOS_DB_NAME", "kilos_grammar")
        db_user = os.getenv("KILOS_DB_USER", "postgres")
        if not db_name or not db_user:
            raise ValueError("KILOS_DB_NAME and KILOS_DB_USER must not be empty")
        return cls(
            db_host=host,
            db_port=db_port,
            db_name=db_name,
            db_user=db_user,
            db_password=os.getenv("KILOS_DB_PASSWORD", ""),
            http_port=http_port,
        )

    def connection_kwargs(self) -> dict[str, object]:
        return {
            "host": self.db_host,
            "port": self.db_port,
            "dbname": self.db_name,
            "user": self.db_user,
            "password": self.db_password,
            "connect_timeout": 3,
        }
