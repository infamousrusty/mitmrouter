"""Suricata IDS – signature-based threat detection on captured PCAP."""
from __future__ import annotations

import json
import subprocess
from pathlib import Path
from typing import Any

from mitmproxy import ctx

from addons.core.addon_base import AbstractAddon

__addon_manifest__ = {
    "name": "suricata_ids",
    "class_name": "SuricataIDS",
    "version": "1.0.0",
    "author": "mitmrouter-core",
    "description": "Run Suricata IDS on session PCAP for signature-based threat detection",
    "dependencies": {"python": [], "system": ["suricata"]},
    "mitmproxy_api_version": ">=9.0.0",
    "supported_modes": ["ethernet", "wifi_ap", "hybrid"],
    "config_schema": {
        "output_dir": {"type": "string", "required": True},
        "pcap_file": {"type": "string", "required": True},
        "suricata_config": {"type": "string", "default": "/etc/suricata/suricata.yaml"},
        "timeout_seconds": {"type": "integer", "default": 180},
    },
    "events": ["shutdown"],
    "health_check": True,
    "test_footprint": "heavy",
    "ci_bundled": False,
    "external_tool_integration": "suricata",
}


class SuricataIDS(AbstractAddon):
    """Run Suricata against a PCAP at session end and parse eve.json alerts."""

    def __init__(self) -> None:
        self._output_dir: Path | None = None
        self._pcap_file: Path | None = None
        self._config_file: str = "/etc/suricata/suricata.yaml"
        self._timeout: int = 180

    def load(self, loader: Any) -> None:  # noqa: ANN401
        loader.add_option(
            name="suricata_output_dir",
            typespec=str,
            default="/tmp/mitmrouter/suricata",
            help="Directory for Suricata eve.json and alert output",
        )
        loader.add_option(
            name="suricata_pcap_file",
            typespec=str,
            default="",
            help="PCAP to run Suricata against",
        )
        loader.add_option(
            name="suricata_config",
            typespec=str,
            default="/etc/suricata/suricata.yaml",
            help="Suricata configuration file path",
        )
        loader.add_option(
            name="suricata_timeout",
            typespec=int,
            default=180,
            help="Suricata subprocess timeout in seconds",
        )

    def configure(self, updated: set[str]) -> None:
        if "suricata_output_dir" in updated:
            self._output_dir = Path(ctx.options.suricata_output_dir)
            self._output_dir.mkdir(parents=True, exist_ok=True)
        if "suricata_pcap_file" in updated and ctx.options.suricata_pcap_file:
            self._pcap_file = Path(ctx.options.suricata_pcap_file)
        if "suricata_config" in updated:
            self._config_file = ctx.options.suricata_config
        if "suricata_timeout" in updated:
            self._timeout = ctx.options.suricata_timeout

    def shutdown(self) -> None:
        if not self._check_tool():
            return
        if self._pcap_file is None or not self._pcap_file.is_file():
            ctx.log.warn("[suricata] no PCAP configured; skipping")
            return

        cmd = [
            "suricata",
            "-r", str(self._pcap_file),
            "-c", self._config_file,
            "-l", str(self._output_dir),
            "--runmode=single",
        ]

        ctx.log.info(f"[suricata] running: {' '.join(cmd)}")
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                timeout=self._timeout,
                check=False,
            )
            if result.returncode == 0:
                alerts = self._parse_alerts()
                ctx.log.info(f"[suricata] complete; {len(alerts)} alerts found")
            else:
                ctx.log.error(
                    f"[suricata] exited {result.returncode}: {result.stderr.decode()[:500]}"
                )
        except subprocess.TimeoutExpired:
            ctx.log.error("[suricata] analysis timed out")
        except Exception as exc:  # noqa: BLE001
            ctx.log.error(f"[suricata] unexpected error: {exc}")

    def _check_tool(self) -> bool:
        try:
            r = subprocess.run(
                ["suricata", "--build-info"],
                capture_output=True,
                timeout=5,
                check=False,
            )
            return r.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            ctx.log.warn("[suricata] suricata not found; addon disabled")
            return False

    def _parse_alerts(self) -> list[dict[str, Any]]:
        """Parse Suricata eve.json for alert entries."""
        eve_file = self._output_dir / "eve.json" if self._output_dir else None
        if not eve_file or not eve_file.is_file():
            return []
        alerts: list[dict[str, Any]] = []
        for line in eve_file.read_text(encoding="utf-8").splitlines():
            try:
                entry = json.loads(line)
                if entry.get("event_type") == "alert":
                    alerts.append(entry)
            except json.JSONDecodeError:
                pass
        return alerts

    def health_check(self) -> dict[str, Any]:  # noqa: ANN401
        available = self._check_tool()
        return {"status": "healthy" if available else "degraded", "suricata_available": available}


addons = [SuricataIDS()]
