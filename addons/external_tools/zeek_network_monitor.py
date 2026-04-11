"""Zeek Network Monitor – high-level protocol analysis via Zeek."""
from __future__ import annotations

import logging
import subprocess
from pathlib import Path
from typing import Any

from mitmproxy import ctx

from addons.core.addon_base import AbstractAddon

logger = logging.getLogger(__name__)

__addon_manifest__ = {
    "name": "zeek_network_monitor",
    "class_name": "ZeekNetworkMonitor",
    "version": "1.0.0",
    "author": "mitmrouter-core",
    "description": "High-level traffic analysis and anomaly detection via Zeek",
    "dependencies": {"python": [], "system": ["zeek"]},
    "mitmproxy_api_version": ">=9.0.0",
    "supported_modes": ["ethernet", "wifi_ap", "hybrid"],
    "config_schema": {
        "output_dir": {"type": "string", "required": True},
        "pcap_file": {"type": "string", "required": True},
        "zeek_scripts_dir": {"type": "string", "required": False},
        "timeout_seconds": {"type": "integer", "default": 120},
    },
    "events": ["shutdown"],
    "health_check": True,
    "test_footprint": "heavy",
    "ci_bundled": False,
    "external_tool_integration": "zeek",
}


class ZeekNetworkMonitor(AbstractAddon):
    """Run Zeek against a PCAP captured during the mitmrouter session."""

    def __init__(self) -> None:
        self._output_dir: Path | None = None
        self._pcap_file: Path | None = None
        self._scripts_dir: Path | None = None
        self._timeout: int = 120
        self._zeek_bin: str = "zeek"

    def load(self, loader: Any) -> None:  # noqa: ANN401
        loader.add_option(
            name="zeek_output_dir",
            typespec=str,
            default="/tmp/mitmrouter/zeek",
            help="Directory for Zeek log output",
        )
        loader.add_option(
            name="zeek_pcap_file",
            typespec=str,
            default="",
            help="PCAP file to analyse with Zeek",
        )
        loader.add_option(
            name="zeek_scripts_dir",
            typespec=str,
            default="",
            help="Path to custom Zeek scripts directory",
        )
        loader.add_option(
            name="zeek_timeout",
            typespec=int,
            default=120,
            help="Zeek subprocess timeout in seconds",
        )

    def configure(self, updated: set[str]) -> None:
        if "zeek_output_dir" in updated:
            self._output_dir = Path(ctx.options.zeek_output_dir)
            self._output_dir.mkdir(parents=True, exist_ok=True)
        if "zeek_pcap_file" in updated and ctx.options.zeek_pcap_file:
            self._pcap_file = Path(ctx.options.zeek_pcap_file)
        if "zeek_scripts_dir" in updated and ctx.options.zeek_scripts_dir:
            self._scripts_dir = Path(ctx.options.zeek_scripts_dir)
        if "zeek_timeout" in updated:
            self._timeout = ctx.options.zeek_timeout

    def shutdown(self) -> None:
        """Run Zeek on captured PCAP at session end."""
        if not self._check_tool():
            return
        if self._pcap_file is None or not self._pcap_file.is_file():
            ctx.log.warn("[zeek] no valid PCAP file configured; skipping analysis")
            return

        cmd = [self._zeek_bin, "-r", str(self._pcap_file), "-C"]
        if self._scripts_dir and self._scripts_dir.is_dir():
            for script in sorted(self._scripts_dir.glob("*.zeek")):
                cmd += ["-s", str(script)]

        ctx.log.info(f"[zeek] running: {' '.join(cmd)}")
        try:
            result = subprocess.run(
                cmd,
                cwd=str(self._output_dir),
                capture_output=True,
                timeout=self._timeout,
                check=False,
            )
            if result.returncode == 0:
                logs = self._parse_logs()
                ctx.log.info(f"[zeek] analysis complete; {len(logs)} log files produced")
            else:
                ctx.log.error(f"[zeek] exited {result.returncode}: {result.stderr.decode()[:500]}")
        except subprocess.TimeoutExpired:
            ctx.log.error("[zeek] analysis timed out")
        except Exception as exc:  # noqa: BLE001
            ctx.log.error(f"[zeek] unexpected error: {exc}")

    def _check_tool(self) -> bool:
        """Return True if Zeek is available."""
        try:
            r = subprocess.run(
                [self._zeek_bin, "--version"],
                capture_output=True,
                timeout=5,
                check=False,
            )
            if r.returncode == 0:
                return True
        except (FileNotFoundError, subprocess.TimeoutExpired):
            pass
        ctx.log.warn("[zeek] zeek not found or not executable; addon disabled")
        return False

    def _parse_logs(self) -> dict[str, list[str]]:
        """Read Zeek *.log files from output directory."""
        logs: dict[str, list[str]] = {}
        for log_file in sorted(self._output_dir.glob("*.log")):
            try:
                logs[log_file.name] = log_file.read_text(encoding="utf-8").splitlines()
            except OSError:
                pass
        return logs

    def health_check(self) -> dict[str, Any]:  # noqa: ANN401
        available = self._check_tool()
        return {"status": "healthy" if available else "degraded", "zeek_available": available}


addons = [ZeekNetworkMonitor()]
