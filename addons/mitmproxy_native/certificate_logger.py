"""Certificate Logger Addon — v2.1-B (cryptography.x509 API).

Captures every TLS certificate seen during a mitmproxy session and
writes a structured JSON inventory to disk.  Uses only the
``cryptography.x509`` API (mitmproxy >= 10.3).

Output file: ``certificates_<ISO8601-timestamp>.json`` in the
configured ``output_dir``.
"""

from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from typing import Any

from cryptography import x509
from cryptography.x509.oid import ExtensionOID, NameOID

from addons.base import AbstractAddon


def _sanitize_name(name: x509.Name) -> dict[str, list[str]]:
    """Extract all RDNs from an x509 Name into a stable dict.

    Returns a mapping like ``{"CN": ["example.com"], "O": ["Acme Corp"]}``.
    """
    result: dict[str, list[str]] = {}
    for attr in name:
        oid_name: str = attr.oid._name  # e.g. "commonName", "organizationName"
        value: str = str(attr.value)
        result.setdefault(oid_name, []).append(value)
    return result


def _extract_sans(cert: x509.Certificate) -> list[str]:
    """Return DNS-name SANs from a certificate, or an empty list."""
    try:
        ext = cert.extensions.get_extension_for_oid(
            ExtensionOID.SUBJECT_ALTERNATIVE_NAME
        )
        return ext.value.get_values_for_type(x509.DNSName)  # type: ignore[attr-defined]
    except x509.ExtensionNotFound:
        return []


def _utc_iso(dt: datetime | None) -> str | None:
    """Format an optional datetime as ISO‑8601 UTC string."""
    if dt is None:
        return None
    return dt.isoformat()


class CertificateLogger(AbstractAddon):
    """Persist every TLS certificate to a JSON inventory."""

    name = "certificate_logger"
    description = "Log every intercepted TLS certificate to a JSON inventory."

    DEFAULT_FILENAME: str = "certificates"

    # ── AbstractAddon interface ──────────────────────────────────────
    @property
    def category(self) -> str:
        return "mitmproxy_native"

    @classmethod
    def manifest(cls) -> dict[str, Any]:
        return {
            "name": cls.name,
            "description": cls.description,
            "category": "mitmproxy_native",
            "version": "2.1.0",
            "min_mitmproxy": "10.3.0",
            "outputs": ["certificates_*.json"],
        }

    def configure(self, output_dir: str) -> None:
        self.output_dir: str = output_dir
        os.makedirs(self.output_dir, exist_ok=True)

    def tls_clienthello(self, flow) -> None:
        """No-op: we capture on ``tls_established`` instead."""
        pass

    def tls_established(self, flow) -> None:
        """mitmproxy calls this hook when a TLS handshake completes.

        In mitmproxy >= 10.3, ``flow.server_conn.certificate`` is a
        ``cryptography.x509.Certificate``.  We delegate to ``_extract()``.
        """
        cert = getattr(flow.server_conn, "certificate", None)
        if cert is None:
            return
        record = self._extract(cert)
        self._persist(record)

    # ── Internals ────────────────────────────────────────────────────
    def _extract(self, cert: x509.Certificate) -> dict[str, Any]:
        """Build a serialisable dict from a ``cryptography.x509.Certificate``.

        Uses only the ``cryptography`` API — **no pyOpenSSL**.
        """
        return {
            "serial_number": format(cert.serial_number, "x"),
            "fingerprint_sha256": cert.fingerprint(
                hashlib.sha256()
            ).hex(),
            "subject": _sanitize_name(cert.subject),
            "issuer": _sanitize_name(cert.issuer),
            "not_valid_before": _utc_iso(cert.not_valid_before_utc),
            "not_valid_after": _utc_iso(cert.not_valid_after_utc),
            "san_dns_names": _extract_sans(cert),
            "version": cert.version.name,
            "signature_algorithm_oid": cert.signature_algorithm_oid.dotted_string,
            "public_key_algorithm": cert.public_key().__class__.__name__,
            "captured_at_utc": datetime.now(timezone.utc).isoformat(),
        }

    def _persist(self, record: dict[str, Any]) -> None:
        timestamp: str = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
        fname: str = f"{self.DEFAULT_FILENAME}_{timestamp}.json"
        path: str = os.path.join(self.output_dir, fname)
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(record, fh, indent=2, sort_keys=True)