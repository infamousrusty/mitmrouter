"""Wireshark/TShark Dissector – protocol dissection via TShark."""

from __future__ import annotations

import subprocess
from pathlib import Path
from typing import Any

from mitmproxy import ctx

from addons.core.addon_base import AbstractAddon

__addon_manifest__ = {
    "name": "wireshark_dissector",
    "class_name": "WiresharkDissector",
    "version": "1.0.0",
    "author": "mitmrouter-core",
    "description": "Full protocol dissection via TShark with optional Lua scripts",
    "dependencies": {"python": [], "system": ["tshark"]},
    "mitmproxy_api_version": ">=9.0.0",
    "supported_modes": ["ethernet", "wifi_ap", "hybrid"],
    "config_schema": {
        "output_dir": {"type": "string", "required": True},
        "pcap_file": {"type": "string", "required": True},
        "lua_scripts_dir": {"type": "string", "required": False},
        "timeout_seconds": {"type": "integer", "default": 120},
    },
    "events": ["shutdown"],
    "health_check": True,
    "test_footprint": "heavy",
    "ci_bundled": False,
    "external_tool_integration": "tshark",
}


class WiresharkDissector(AbstractAddon):
    """Run TShark against a PCAP file and emit JSON dissection output."""

    def __init__(self) -> None:
        self._output_dir: Path | None = None
        self._pcap_file: Path | None = None
        self._lua_dir: Path | None = None
        self._timeout: int = 120

    def load(self, loader: Any) -> None:  # noqa: ANN401
        loader.add_option(
            name="tshark_output_dir",
            typespec=str,
            default="/tmp/mitmrouter/tshark",
            help="Directory for TShark dissection output",
        )
        loader.add_option(
            name="tshark_pcap_file",
            typespec=str,
            default="",
            help="PCAP file to dissect",
        )
        loader.add_option(
            name="tshark_lua_dir",
            typespec=str,
            default="",
            help="Directory containing Lua dissector scripts",
        )
        loader.add_option(
            name="tshark_timeout",
            typespec=int,
            default=120,
            help="TShark subprocess timeout in seconds",
        )

    def configure(self, updated: set[str]) -> None:
        if "tshark_output_dir" in updated:
            self._output_dir = Path(ctx.options.tshark_output_dir)
            self._output_dir.mkdir(parents=True, exist_ok=True)
        if "tshark_pcap_file" in updated and ctx.options.tshark_pcap_file:
            self._pcap_file = Path(ctx.options.tshark_pcap_file)
        if "tshark_lua_dir" in updated and ctx.options.tshark_lua_dir:
            self._lua_dir = Path(ctx.options.tshark_lua_dir)
        if "tshark_timeout" in updated:
            self._timeout = ctx.options.tshark_timeout

    def shutdown(self) -> None:
        if not self._check_tool():
            return
        if self._pcap_file is None or not self._pcap_file.is_file():
            ctx.log.warn("[tshark] no PCAP configured; skipping")
            return

        out_file = self._output_dir / "dissection.json" if self._output_dir else None
        if out_file is None:
            return

        cmd = ["tshark", "-r", str(self._pcap_file), "-T", "json"]
        if self._lua_dir and self._lua_dir.is_dir():
            for lua_script in sorted(self._lua_dir.glob("*.lua")):
                cmd += ["-X", f"lua_script:{lua_script}"]

        ctx.log.info(f"[tshark] running: {' '.join(cmd)}")
        try:
            result = subprocess.run(
                cmd,
                capture_output=True,
                timeout=self._timeout,
                check=False,
            )
            if result.returncode == 0:
                out_file.write_bytes(result.stdout)
                ctx.log.info(f"[tshark] dissection written → {out_file}")
            else:
                ctx.log.error(
                    f"[tshark] exited {result.returncode}: {result.stderr.decode()[:500]}"
                )
        except subprocess.TimeoutExpired:
            ctx.log.error("[tshark] dissection timed out")
        except Exception as exc:  # noqa: BLE001
            ctx.log.error(f"[tshark] unexpected error: {exc}")

    def _check_tool(self) -> bool:
        try:
            r = subprocess.run(
                ["tshark", "--version"],
                capture_output=True,
                timeout=5,
                check=False,
            )
            return r.returncode == 0
        except (FileNotFoundError, subprocess.TimeoutExpired):
            ctx.log.warn("[tshark] tshark not found; addon disabled")
            return False

    def health_check(self) -> dict[str, Any]:  # noqa: ANN401
        available = self._check_tool()
        return {
            "status": "healthy" if available else "degraded",
            "tshark_available": available,
        }


addons = [WiresharkDissector()]
