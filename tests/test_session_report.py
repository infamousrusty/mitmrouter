"""Light unit tests for the Session Report addon."""

from __future__ import annotations

import os
import shutil
import tempfile
from pathlib import Path

import pytest

from addons.reporting.session_report import SessionReportAddon


def _fixture_path(name: str) -> str:
    """Return the absolute path to a test fixture file."""
    return os.path.join(os.path.dirname(__file__), "fixtures", name)


class TestSessionReportScan:
    """Verify ``_scan()`` correctly reads fixture artefacts."""

    def test_scan_finds_inventory_endpoints(self):
        addon = SessionReportAddon()
        with tempfile.TemporaryDirectory() as tmpdir:
            # Copy fixture into tmpdir
            shutil.copy(_fixture_path("inventory_sample.json"),
                        os.path.join(tmpdir, "inventory_20240101T000000Z.json"))
            addon.configure(output_dir=tmpdir)
            data = addon._scan()

            assert data["endpoint_count"] == 4

    def test_scan_finds_certificates(self):
        addon = SessionReportAddon()
        with tempfile.TemporaryDirectory() as tmpdir:
            shutil.copy(_fixture_path("certificates_sample.json"),
                        os.path.join(tmpdir, "certificates_20240101T000000Z.json"))
            addon.configure(output_dir=tmpdir)
            data = addon._scan()

            assert data["cert_count"] == 2

    def test_scan_finds_openapi_paths(self):
        addon = SessionReportAddon()
        with tempfile.TemporaryDirectory() as tmpdir:
            shutil.copy(_fixture_path("api_spec_sample.yaml"),
                        os.path.join(tmpdir, "api_spec.yaml"))
            addon.configure(output_dir=tmpdir)
            data = addon._scan()

            assert data["openapi_path_count"] == 4
            assert "/v1/users" in data["openapi_paths"]
            assert "/v1/health" in data["openapi_paths"]

    def test_scan_computes_top_hosts(self):
        addon = SessionReportAddon()
        with tempfile.TemporaryDirectory() as tmpdir:
            shutil.copy(_fixture_path("traffic_sample.jsonl"),
                        os.path.join(tmpdir, "traffic.jsonl"))
            addon.configure(output_dir=tmpdir)
            data = addon._scan()

            assert data["total_flows"] == 12
            assert data["unique_hosts"] == 3
            # api.example.com should be top
            top_host, top_count = data["top_hosts"][0]
            assert top_host == "api.example.com"
            assert top_count == 6

    def test_scan_empty_directory(self):
        addon = SessionReportAddon()
        with tempfile.TemporaryDirectory() as tmpdir:
            addon.configure(output_dir=tmpdir)
            data = addon._scan()

            assert data["total_flows"] == 0
            assert data["endpoint_count"] == 0
            assert data["cert_count"] == 0
            assert data["openapi_path_count"] == 0
            assert data["top_hosts"] == []


class TestSessionReportRender:
    """Verify HTML and Markdown output is well‑formed."""

    def test_render_html_produces_valid_html(self):
        addon = SessionReportAddon()
        with tempfile.TemporaryDirectory() as tmpdir:
            shutil.copy(_fixture_path("traffic_sample.jsonl"),
                        os.path.join(tmpdir, "traffic.jsonl"))
            shutil.copy(_fixture_path("inventory_sample.json"),
                        os.path.join(tmpdir, "inventory_20240101T000000Z.json"))
            shutil.copy(_fixture_path("certificates_sample.json"),
                        os.path.join(tmpdir, "certificates_20240101T000000Z.json"))
            shutil.copy(_fixture_path("api_spec_sample.yaml"),
                        os.path.join(tmpdir, "api_spec.yaml"))

            addon.configure(output_dir=tmpdir)
            data = addon._scan()
            html = addon._render_html(data)

            assert "<!DOCTYPE html>" in html
            assert "<title>MitmRouter Session Report" in html
            assert "api.example.com" in html
            assert "<table>" in html
            assert "</html>" in html

    def test_render_md_produces_expected_sections(self):
        addon = SessionReportAddon()
        with tempfile.TemporaryDirectory() as tmpdir:
            shutil.copy(_fixture_path("traffic_sample.jsonl"),
                        os.path.join(tmpdir, "traffic.jsonl"))
            addon.configure(output_dir=tmpdir)
            data = addon._scan()
            md = addon._render_md(data)

            assert "# MitmRouter Session Report" in md
            assert "## Summary" in md
            assert "## Top 10 Hosts" in md
            assert "| api.example.com" in md

    def test_shutdown_writes_both_files(self):
        addon = SessionReportAddon()
        with tempfile.TemporaryDirectory() as tmpdir:
            shutil.copy(_fixture_path("traffic_sample.jsonl"),
                        os.path.join(tmpdir, "traffic.jsonl"))
            addon.configure(output_dir=tmpdir)
            addon.shutdown()

            assert os.path.isfile(os.path.join(tmpdir, "report.html"))
            assert os.path.isfile(os.path.join(tmpdir, "report.md"))

            with open(os.path.join(tmpdir, "report.html"), encoding="utf-8") as fh:
                assert len(fh.read()) > 100
            with open(os.path.join(tmpdir, "report.md"), encoding="utf-8") as fh:
                assert len(fh.read()) > 50