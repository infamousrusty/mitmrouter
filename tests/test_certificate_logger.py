"""Light unit tests for the certificate_logger addon (cryptography.x509 API)."""

from __future__ import annotations

import datetime
import os
import tempfile

import pytest
from cryptography import x509
from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import rsa
from cryptography.x509.oid import NameOID

from addons.mitmproxy_native.certificate_logger import CertificateLogger


def _build_self_signed_cert(
    common_name: str = "example.com",
    san_dns: tuple[str, ...] = ("example.com", "www.example.com"),
) -> x509.Certificate:
    """Generate a real self-signed certificate fixture."""
    key = rsa.generate_private_key(public_exponent=65537, key_size=2048)

    subject = issuer = x509.Name(
        [
            x509.NameAttribute(NameOID.COUNTRY_NAME, "US"),
            x509.NameAttribute(NameOID.STATE_OR_PROVINCE_NAME, "California"),
            x509.NameAttribute(NameOID.LOCALITY_NAME, "San Francisco"),
            x509.NameAttribute(NameOID.ORGANIZATION_NAME, "Test Org"),
            x509.NameAttribute(NameOID.COMMON_NAME, common_name),
        ]
    )

    san = x509.SubjectAlternativeName(
        [x509.DNSName(dns) for dns in san_dns]
    )

    now = datetime.datetime(2024, 1, 1, 0, 0, 0, tzinfo=datetime.timezone.utc)
    cert = (
        x509.CertificateBuilder()
        .subject_name(subject)
        .issuer_name(issuer)
        .public_key(key.public_key())
        .serial_number(1234567890)
        .not_valid_before(now)
        .not_valid_after(now + datetime.timedelta(days=365))
        .add_extension(san, critical=False)
        .sign(key, hashes.SHA256())
    )
    return cert


# ── Tests ────────────────────────────────────────────────────────────


class TestCertificateLoggerExtract:
    """Verify ``_extract()`` works with a real ``x509.Certificate``."""

    def test_extract_common_name(self):
        cert = _build_self_signed_cert(common_name="api.example.io")
        addon = CertificateLogger()
        record = addon._extract(cert)

        cn_list = record["subject"].get("commonName", [])
        assert "api.example.io" in cn_list

    def test_extract_san_dns_names(self):
        cert = _build_self_signed_cert(
            common_name="multi.test",
            san_dns=("multi.test", "alias.multi.test", "*.multi.test"),
        )
        addon = CertificateLogger()
        record = addon._extract(cert)

        sans = record["san_dns_names"]
        assert "multi.test" in sans
        assert "alias.multi.test" in sans
        assert "*.multi.test" in sans

    def test_extract_validity(self):
        cert = _build_self_signed_cert()
        addon = CertificateLogger()
        record = addon._extract(cert)

        assert record["not_valid_before"] is not None
        assert record["not_valid_after"] is not None
        assert record["not_valid_before"].startswith("2024-01-01")

    def test_extract_fingerprint_is_hex(self):
        cert = _build_self_signed_cert()
        addon = CertificateLogger()
        record = addon._extract(cert)

        fp = record["fingerprint_sha256"]
        assert len(fp) == 64
        assert all(c in "0123456789abcdef" for c in fp)

    def test_extract_issuer(self):
        cert = _build_self_signed_cert(common_name="selfsigned.test")
        addon = CertificateLogger()
        record = addon._extract(cert)

        # Self-signed → issuer == subject CN
        issuer_cn = record["issuer"].get("commonName", [])
        subject_cn = record["subject"].get("commonName", [])
        assert issuer_cn == subject_cn

    def test_extract_serial_number(self):
        cert = _build_self_signed_cert()
        addon = CertificateLogger()
        record = addon._extract(cert)

        # Serial 1234567890 → "499602d2" in hex
        assert record["serial_number"] == "499602d2"


class TestCertificateLoggerPersist:
    """Verify ``_persist()`` writes a valid JSON file."""

    def test_persist_writes_json_to_output_dir(self):
        cert = _build_self_signed_cert()
        addon = CertificateLogger()
        with tempfile.TemporaryDirectory() as tmpdir:
            addon.configure(output_dir=tmpdir)
            record = addon._extract(cert)
            addon._persist(record)

            files = os.listdir(tmpdir)
            json_files = [f for f in files if f.endswith(".json")]
            assert len(json_files) == 1, f"Expected 1 JSON file, got {json_files}"

            with open(os.path.join(tmpdir, json_files[0])) as fh:
                import json

                data = json.load(fh)
            assert data["serial_number"] == record["serial_number"]