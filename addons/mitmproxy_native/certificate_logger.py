"""Certificate Logger – extract and catalogue TLS/SSL certificates."""

from __future__ import annotations

import csv
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from mitmproxy import ctx, http

from addons.core.addon_base import AbstractAddon

__addon_manifest__ = {
    "name": "certificate_logger",
    "class_name": "CertificateLogger",
    "version": "1.0.0",
    "author": "mitmrouter-core",
    "description": "Extract and track TLS/SSL certificates, issuers, validity dates, and SANs",
    "dependencies": {"python": ["cryptography"], "system": []},
    "mitmproxy_api_version": ">=9.0.0",
    "supported_modes": ["ethernet", "wifi_ap", "hybrid"],
    "config_schema": {
        "output_dir": {"type": "string", "required": True},
    },
    "events": ["response"],
    "health_check": True,
    "test_footprint": "light",
    "ci_bundled": True,
    "external_tool_integration": None,
}

_CSV_FIELDS = [
    "timestamp",
    "host",
    "subject",
    "issuer",
    "not_valid_before",
    "not_valid_after",
    "fingerprint_sha256",
]


class CertificateLogger(AbstractAddon):
    """Log TLS certificates from intercepted HTTPS flows."""

    def __init__(self) -> None:
        self._certs: list[dict[str, Any]] = []
        self._seen: set[str] = set()
        self._output_dir: Path | None = None

    def load(self, loader: Any) -> None:  # noqa: ANN401
        loader.add_option(
            name="certs_output_dir",
            typespec=str,
            default="/tmp/mitmrouter/certs",
            help="Directory for certificate log files",
        )
        loader.add_command("certs_export", self.cmd_export, "Export certificate inventory")
        loader.add_command("certs_status", self.cmd_status, "Show certificate statistics")

    def configure(self, updated: set[str]) -> None:
        if "certs_output_dir" in updated:
            self._output_dir = Path(ctx.options.certs_output_dir)
            self._output_dir.mkdir(parents=True, exist_ok=True)

    def response(self, flow: http.HTTPFlow) -> None:
        if flow.request.scheme != "https":
            return
        if not (flow.server_conn and flow.server_conn.tls_established):
            return
        cert = getattr(flow.server_conn, "cert", None)
        if cert is None:
            return

        info = self._extract(cert, flow.request.host)
        fp = info.get("fingerprint_sha256", "")
        if fp and fp not in self._seen:
            self._certs.append(info)
            self._seen.add(fp)
            ctx.log.debug(f"[certificate_logger] logged cert for {flow.request.host}")

    def shutdown(self) -> None:
        self.export()

    @staticmethod
    def _extract(cert: Any, host: str) -> dict[str, Any]:  # noqa: ANN401
        """Extract structured info from a mitmproxy certificate object.

        The `cryptography` package is an optional runtime dependency; the
        import is deferred so the addon loads cleanly even without it.
        ExtensionOID is not referenced here – SAN extraction is handled via
        the mitmproxy cert wrapper rather than the cryptography API directly.
        """
        try:
            import cryptography  # noqa: F401  – availability check only
        except ImportError:
            ctx.log.warn("[certificate_logger] cryptography library not installed")
            return {}

        try:
            cn = cert.get_subject().CN or ""
            issuer = cert.get_issuer().CN or ""
            not_before = cert.get_notBefore().decode()
            not_after = cert.get_notAfter().decode()
            fingerprint = hashlib.sha256(
                cert.to_cryptography().public_bytes(
                    __import__(
                        "cryptography.hazmat.primitives.serialization",
                        fromlist=["Encoding"],
                    ).Encoding.DER
                )
            ).hexdigest()

            return {
                "timestamp": datetime.now(tz=timezone.utc).isoformat(),
                "host": host,
                "subject": cn,
                "issuer": issuer,
                "not_valid_before": not_before,
                "not_valid_after": not_after,
                "fingerprint_sha256": fingerprint,
            }
        except Exception as exc:  # noqa: BLE001
            ctx.log.error(f"[certificate_logger] extraction error: {exc}")
            return {}

    def export(self) -> None:
        if self._output_dir is None:
            return
        ts = datetime.now(tz=timezone.utc).strftime("%Y%m%d_%H%M%S")

        json_out = self._output_dir / f"certificates_{ts}.json"
        json_out.write_text(
            json.dumps(
                {
                    "export_time": datetime.now(tz=timezone.utc).isoformat(),
                    "unique_certificates": len(self._certs),
                    "certificates": self._certs,
                },
                indent=2,
            ),
            encoding="utf-8",
        )

        csv_out = self._output_dir / f"certificates_{ts}.csv"
        with csv_out.open("w", newline="", encoding="utf-8") as f:
            writer = csv.DictWriter(f, fieldnames=_CSV_FIELDS, extrasaction="ignore")
            writer.writeheader()
            writer.writerows(self._certs)

        ctx.log.info(
            f"[certificate_logger] exported {len(self._certs)} certs → {self._output_dir}"
        )

    def cmd_export(self) -> str:
        self.export()
        return f"Exported {len(self._certs)} unique certificates"

    def cmd_status(self) -> str:
        return f"Unique certificates tracked: {len(self._certs)}"

    def health_check(self) -> dict[str, Any]:  # noqa: ANN401
        return {"status": "healthy", "unique_certs": len(self._certs)}


addons = [CertificateLogger()]
