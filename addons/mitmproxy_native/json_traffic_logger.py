"""JSON Traffic Logger – structured JSONL log of all flows."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from mitmproxy import ctx, http

from addons.core.addon_base import AbstractAddon

__addon_manifest__ = {
    "name": "json_traffic_logger",
    "class_name": "JSONTrafficLogger",
    "version": "1.0.0",
    "author": "mitmrouter-core",
    "description": "Write all flows to structured JSONL for downstream analysis (ELK, Splunk)",
    "dependencies": {"python": [], "system": []},
    "mitmproxy_api_version": ">=9.0.0",
    "supported_modes": ["ethernet", "wifi_ap", "hybrid"],
    "config_schema": {
        "output_file": {"type": "string", "required": True},
        "body_preview_bytes": {"type": "integer", "default": 512},
        "redact_headers": {"type": "array", "default": ["authorization", "cookie"]},
    },
    "events": ["response", "error"],
    "health_check": True,
    "test_footprint": "light",
    "ci_bundled": True,
    "external_tool_integration": None,
}

_DEFAULT_REDACT = frozenset(["authorization", "cookie", "set-cookie", "x-api-key"])


class JSONTrafficLogger(AbstractAddon):
    """Append every intercepted flow to a JSONL file."""

    def __init__(self) -> None:
        self._output_file: Path | None = None
        self._preview_bytes: int = 512
        self._redact: frozenset[str] = _DEFAULT_REDACT
        self._flow_count: int = 0
        self._fh: Any = None  # open file handle

    def load(self, loader: Any) -> None:  # noqa: ANN401
        loader.add_option(
            name="traffic_log_file",
            typespec=str,
            default="/tmp/mitmrouter/traffic.jsonl",
            help="Path for the JSONL traffic log",
        )
        loader.add_option(
            name="traffic_body_preview",
            typespec=int,
            default=512,
            help="Maximum bytes of body to include in each log entry",
        )

    def configure(self, updated: set[str]) -> None:
        if "traffic_log_file" in updated:
            if self._fh:
                self._fh.close()
            self._output_file = Path(ctx.options.traffic_log_file)
            self._output_file.parent.mkdir(parents=True, exist_ok=True)
            self._fh = self._output_file.open("a", encoding="utf-8")
        if "traffic_body_preview" in updated:
            self._preview_bytes = ctx.options.traffic_body_preview

    def running(self) -> None:
        ctx.log.info("[json_traffic_logger] started; logging to %s", self._output_file)

    def shutdown(self) -> None:
        if self._fh:
            self._fh.flush()
            self._fh.close()
            self._fh = None
        ctx.log.info("[json_traffic_logger] logged %d flows", self._flow_count)

    def response(self, flow: http.HTTPFlow) -> None:
        self._write(flow, error=None)

    def error(self, flow: http.HTTPFlow) -> None:
        self._write(flow, error=str(flow.error) if flow.error else "unknown error")

    def _write(self, flow: http.HTTPFlow, error: str | None) -> None:
        if self._fh is None:
            return

        def _safe_headers(headers: Any) -> dict[str, str]:  # noqa: ANN401
            return {
                k: ("[REDACTED]" if k.lower() in self._redact else v)
                for k, v in dict(headers).items()
            }

        def _body_preview(content: bytes | None) -> str | None:
            if not content:
                return None
            preview = content[: self._preview_bytes]
            try:
                return preview.decode("utf-8", errors="replace")
            except Exception:  # noqa: BLE001
                return preview.hex()

        entry: dict[str, Any] = {
            "timestamp": datetime.now(tz=timezone.utc).isoformat(),
            "flow_id": flow.id,
            "error": error,
            "request": {
                "method": flow.request.method,
                "url": flow.request.url,
                "http_version": flow.request.http_version,
                "headers": _safe_headers(flow.request.headers),
                "body_preview": _body_preview(flow.request.content),
            },
        }

        if flow.response:
            entry["response"] = {
                "status_code": flow.response.status_code,
                "http_version": flow.response.http_version,
                "headers": _safe_headers(flow.response.headers),
                "body_preview": _body_preview(flow.response.content),
            }

        self._fh.write(json.dumps(entry, ensure_ascii=False) + "\n")
        self._fh.flush()
        self._flow_count += 1

    def health_check(self) -> dict[str, Any]:  # noqa: ANN401
        return {"status": "healthy", "flows_logged": self._flow_count}


addons = [JSONTrafficLogger()]
