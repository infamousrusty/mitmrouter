"""Session Report – post-session HTML/Markdown summary addon.

Consolidates outputs from all other addons into a single human-readable
report at the end of each mitmrouter session.

This is a Phase 2 stub.  The manifest and class skeleton are intentionally
minimal so the registry does not raise on discovery.  Full implementation
will be completed in the Phase 2 milestone (see docs/phase-roadmaps/phase-2.md).
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from mitmproxy import ctx

from addons.core.addon_base import AbstractAddon

__addon_manifest__ = {
    "name": "session_report",
    "class_name": "SessionReport",
    "version": "0.1.0",
    "author": "mitmrouter-core",
    "description": "[Phase 2 stub] Post-session HTML/Markdown summary report",
    "dependencies": {"python": [], "system": []},
    "mitmproxy_api_version": ">=9.0.0",
    "supported_modes": ["ethernet", "wifi_ap", "hybrid"],
    "config_schema": {
        "output_dir": {"type": "string", "required": True},
        "format": {
            "type": "string",
            "enum": ["html", "markdown", "both"],
            "default": "both",
        },
    },
    "events": ["shutdown"],
    "health_check": True,
    "test_footprint": "light",
    "ci_bundled": True,
    "external_tool_integration": None,
    "phase": 2,
    "status": "stub",
}


class SessionReport(AbstractAddon):
    """Produce a post-session summary report.  Phase 2 stub."""

    def __init__(self) -> None:
        self._output_dir: Path | None = None
        self._format: str = "both"

    def load(self, loader: Any) -> None:  # noqa: ANN401
        loader.add_option(
            name="report_output_dir",
            typespec=str,
            default="/tmp/mitmrouter/reports",
            help="Directory for session reports",
        )
        loader.add_option(
            name="report_format",
            typespec=str,
            default="both",
            help="Report format: html | markdown | both",
        )

    def configure(self, updated: set[str]) -> None:
        if "report_output_dir" in updated:
            self._output_dir = Path(ctx.options.report_output_dir)
            self._output_dir.mkdir(parents=True, exist_ok=True)
        if "report_format" in updated:
            self._format = ctx.options.report_format

    def shutdown(self) -> None:
        ctx.log.info(
            "[session_report] Phase 2 stub — report generation not yet implemented. "
            "See docs/phase-roadmaps/phase-2.md for the full specification."
        )

    def health_check(self) -> dict[str, Any]:  # noqa: ANN401
        return {"status": "healthy", "note": "Phase 2 stub — not yet implemented"}


addons = [SessionReport()]
