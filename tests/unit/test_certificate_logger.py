"""Unit tests for certificate_logger addon."""

from __future__ import annotations

import pytest

from addons.mitmproxy_native.certificate_logger import CertificateLogger


@pytest.mark.light
class TestCertificateLogger:
    """Isolated unit tests – no I/O, no real TLS certs."""

    def test_skips_http_flows(self, sample_http_flow):
        logger = CertificateLogger()
        logger.response(sample_http_flow)
        assert len(logger._certs) == 0

    def test_skips_untested_tls(self, https_flow):
        """If server_conn has no cert, nothing should be logged."""
        https_flow.server_conn.cert = None
        logger = CertificateLogger()
        logger.response(https_flow)
        assert len(logger._certs) == 0

    def test_deduplicates_by_fingerprint(self):
        logger = CertificateLogger()
        fake_cert = {
            "timestamp": "2026-04-11T00:00:00+00:00",
            "host": "example.com",
            "subject": "example.com",
            "issuer": "Let's Encrypt",
            "not_valid_before": "20250101000000Z",
            "not_valid_after": "20260101000000Z",
            "fingerprint_sha256": "deadbeef",
        }
        logger._certs.append(fake_cert)
        logger._seen.add("deadbeef")

        assert "deadbeef" in logger._seen
        assert len(logger._certs) == 1

    def test_export_writes_files(self, tmp_path):
        logger = CertificateLogger()
        logger._output_dir = tmp_path
        logger._certs = [
            {
                "timestamp": "2026-04-11T00:00:00+00:00",
                "host": "test.example.com",
                "subject": "test.example.com",
                "issuer": "Test CA",
                "not_valid_before": "20250101000000Z",
                "not_valid_after": "20260101000000Z",
                "fingerprint_sha256": "abc123",
            }
        ]
        logger.export()

        assert any(tmp_path.glob("certificates_*.json"))
        assert any(tmp_path.glob("certificates_*.csv"))
