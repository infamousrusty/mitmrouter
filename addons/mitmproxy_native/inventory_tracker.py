"""Inventory Tracker – extract and catalogue HTTP/S endpoints and APIs."""
from __future__ import annotations

import csv
import json
import time
from collections import defaultdict
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from mitmproxy import ctx, http

from addons.core.addon_base import AbstractAddon

__addon_manifest__ = {
    "name": "inventory_tracker",
    "class_name": "InventoryTracker",
    "version": "1.0.0",
    "author": "mitmrouter-core",
    "description": "Extract and inventory HTTP/HTTPS endpoints, domains, and APIs",
    "dependencies": {"python": [], "system": []},
    "mitmproxy_api_version": ">=9.0.0",
    "supported_modes": ["ethernet", "wifi_ap", "hybrid"],
    "config_schema": {
        "output_dir": {"type": "string", "required": True},
        "format": {"type": "string", "enum": ["json", "csv", "both"], "default": "json"},
        "include_query_params": {"type": "boolean", "default": True},
    },
    "events": ["response"],
    "health_check": True,
    "test_footprint": "light",
    "ci_bundled": True,
    "external_tool_integration": None,
}


class InventoryTracker(AbstractAddon):
    """Track all HTTP/HTTPS endpoints, domains, and APIs observed in traffic."""

    def __init__(self) -> None:
        self._endpoints: list[dict[str, Any]] = []
        self._seen: defaultdict[str, int] = defaultdict(int)
        self._output_dir: Path | None = None
        self._format: str = "json"
        self._include_query: bool = True

    # ------------------------------------------------------------------ #
    # Lifecycle                                                           #
    # ------------------------------------------------------------------ #

    def load(self, loader: Any) -> None:  # noqa: ANN401
        loader.add_option(
            name="inventory_output_dir",
            typespec=str,
            default="/tmp/mitmrouter/inventory",
            help="Directory to write inventory files",
        )
        loader.add_option(
            name="inventory_format",
            typespec=str,
            default="json",
            help="Output format: json | csv | both",
        )
        loader.add_option(
            name="inventory_include_query",
            typespec=bool,
            default=True,
            help="Include query parameters in tracking",
        )
        loader.add_command("inventory_export", self.cmd_export, "Export current inventory")
        loader.add_command("inventory_status", self.cmd_status, "Show inventory statistics")

    def configure(self, updated: set[str]) -> None:
        if "inventory_output_dir" in updated:
            self._output_dir = Path(ctx.options.inventory_output_dir)
            self._output_dir.mkdir(parents=True, exist_ok=True)
        if "inventory_format" in updated:
            self._format = ctx.options.inventory_format
        if "inventory_include_query" in updated:
            self._include_query = ctx.options.inventory_include_query

    # ------------------------------------------------------------------ #
    # Event hooks                                                         #
    # ------------------------------------------------------------------ #

    def response(self, flow: http.HTTPFlow) -> None:
        key = f"{flow.request.method}:{flow.request.host}{flow.request.path}"
        self._seen[key] += 1

        entry: dict[str, Any] = {
            "timestamp": datetime.now(tz=timezone.utc).isoformat(),
            "host": flow.request.host,
            "scheme": flow.request.scheme,
            "method": flow.request.method,
            "path": flow.request.path,
            "status_code": flow.response.status_code,
            "content_type": flow.response.headers.get("content-type", ""),
            "content_length": len(flow.response.content),
            "seen_count": self._seen[key],
        }

        if self._include_query and flow.request.query:
            entry["query_params"] = dict(flow.request.query)

        self._endpoints.append(entry)

        if len(self._endpoints) % 50 == 0:
            ctx.log.info(f"[inventory_tracker] tracked {len(self._endpoints)} flows")

    def shutdown(self) -> None:
        self.export()

    # ------------------------------------------------------------------ #
    # Export                                                              #
    # ------------------------------------------------------------------ #

    def export(self) -> None:
        """Write inventory to disk."""
        if self._output_dir is None:
            ctx.log.warn("[inventory_tracker] output_dir not configured; skipping export")
            return

        ts = datetime.now(tz=timezone.utc).strftime("%Y%m%d_%H%M%S")

        if self._format in ("json", "both"):
            out = self._output_dir / f"inventory_{ts}.json"
            out.write_text(
                json.dumps(
                    {
                        "export_time": datetime.now(tz=timezone.utc).isoformat(),
                        "total_flows": len(self._endpoints),
                        "unique_endpoints": len(self._seen),
                        "endpoints": self._endpoints,
                    },
                    indent=2,
                ),
                encoding="utf-8",
            )
            ctx.log.info(f"[inventory_tracker] exported JSON → {out}")

        if self._format in ("csv", "both"):
            out = self._output_dir / f"inventory_{ts}.csv"
            fields = ["timestamp", "host", "scheme", "method", "path", "status_code",
                      "content_type", "content_length", "seen_count"]
            with out.open("w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=fields, extrasaction="ignore")
                writer.writeheader()
                writer.writerows(self._endpoints)
            ctx.log.info(f"[inventory_tracker] exported CSV → {out}")

    # ------------------------------------------------------------------ #
    # Commands                                                            #
    # ------------------------------------------------------------------ #

    def cmd_export(self) -> str:
        self.export()
        return f"Exported {len(self._endpoints)} endpoint records"

    def cmd_status(self) -> str:
        return (
            f"Flows tracked   : {len(self._endpoints)}\n"
            f"Unique endpoints: {len(self._seen)}"
        )

    def health_check(self) -> dict[str, Any]:  # noqa: ANN401
        return {"status": "healthy", "flows": len(self._endpoints)}


addons = [InventoryTracker()]
