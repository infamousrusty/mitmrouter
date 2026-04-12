"""Integration tests – multiple addons sharing the same flow context."""

from __future__ import annotations

from pathlib import Path

import pytest
from mitmproxy import http
from mitmproxy.test import taddons


@pytest.mark.light
def test_inventory_and_json_logger_coexist(
    sample_http_flow: http.HTTPFlow,
    tmp_path: Path,
) -> None:
    """Both addons should handle the same flow without conflict."""
    from addons.mitmproxy_native.inventory_tracker import InventoryTracker
    from addons.mitmproxy_native.json_traffic_logger import JSONTrafficLogger

    inventory = InventoryTracker()
    inventory._output_dir = tmp_path / "inventory"
    inventory._output_dir.mkdir()

    logger = JSONTrafficLogger()
    log_file = tmp_path / "traffic.jsonl"
    logger._output_file = log_file
    logger._fh = log_file.open("a", encoding="utf-8")

    with taddons.context(inventory, logger) as tctx:
        tctx.master.addons.trigger(http.HttpResponseHook(sample_http_flow))

    logger._fh.close()

    assert len(inventory._endpoints) == 1
    assert log_file.exists()
    lines = log_file.read_text().splitlines()
    assert len(lines) >= 1


@pytest.mark.light
def test_inventory_and_api_spec_coexist(
    sample_http_flow: http.HTTPFlow,
    sample_post_flow: http.HTTPFlow,
    tmp_path: Path,
) -> None:
    """inventory_tracker and api_spec_extractor should coexist on the same flows."""
    from addons.mitmproxy_native.api_spec_extractor import APISpecExtractor
    from addons.mitmproxy_native.inventory_tracker import InventoryTracker

    inventory = InventoryTracker()
    inventory._output_dir = tmp_path

    extractor = APISpecExtractor()
    extractor._output_file = tmp_path / "spec.yaml"

    with taddons.context(inventory, extractor) as tctx:
        tctx.master.addons.trigger(http.HttpResponseHook(sample_http_flow))
        tctx.master.addons.trigger(http.HttpResponseHook(sample_post_flow))

    assert len(inventory._endpoints) == 2
    assert "/v1/users" in extractor._spec["paths"]
    assert "get" in extractor._spec["paths"]["/v1/users"]
    assert "post" in extractor._spec["paths"]["/v1/users"]
