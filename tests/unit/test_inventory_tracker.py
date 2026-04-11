"""Unit tests for inventory_tracker addon."""
from __future__ import annotations

import json

import pytest

from addons.mitmproxy_native.inventory_tracker import InventoryTracker


@pytest.mark.light
class TestInventoryTracker:
    """Isolated unit tests – no I/O."""

    def test_tracks_single_endpoint(self, sample_http_flow):
        tracker = InventoryTracker()
        tracker.response(sample_http_flow)

        assert len(tracker._endpoints) == 1
        entry = tracker._endpoints[0]
        assert entry["host"] == "api.example.com"
        assert entry["method"] == "GET"
        assert entry["status_code"] == 200
        assert entry["path"] == "/v1/users"

    def test_increments_seen_count_on_duplicate(self, sample_http_flow):
        tracker = InventoryTracker()
        tracker.response(sample_http_flow)
        tracker.response(sample_http_flow)

        key = "GET:api.example.com/v1/users"
        assert tracker._seen[key] == 2
        assert tracker._endpoints[-1]["seen_count"] == 2

    def test_export_json(self, sample_http_flow, tmp_path):
        tracker = InventoryTracker()
        tracker._output_dir = tmp_path
        tracker._format = "json"
        tracker.response(sample_http_flow)
        tracker.export()

        json_files = list(tmp_path.glob("inventory_*.json"))
        assert len(json_files) == 1

        data = json.loads(json_files[0].read_text())
        assert data["total_flows"] == 1
        assert len(data["endpoints"]) == 1

    def test_export_csv(self, sample_http_flow, tmp_path):
        tracker = InventoryTracker()
        tracker._output_dir = tmp_path
        tracker._format = "csv"
        tracker.response(sample_http_flow)
        tracker.export()

        csv_files = list(tmp_path.glob("inventory_*.csv"))
        assert len(csv_files) == 1

        lines = csv_files[0].read_text().splitlines()
        assert lines[0].startswith("timestamp")  # header row
        assert len(lines) == 2  # header + 1 data row

    def test_no_output_dir_does_not_raise(self, sample_http_flow):
        tracker = InventoryTracker()
        tracker.response(sample_http_flow)
        tracker.export()  # should log a warning and return cleanly
