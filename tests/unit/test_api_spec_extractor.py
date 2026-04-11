"""Unit tests for api_spec_extractor addon."""

from __future__ import annotations

import json

import pytest

from addons.mitmproxy_native.api_spec_extractor import APISpecExtractor


@pytest.mark.light
class TestAPISpecExtractor:
    def test_tracks_server(self, sample_http_flow):
        extractor = APISpecExtractor()
        extractor.response(sample_http_flow)
        assert any(s["url"] == "http://api.example.com" for s in extractor._spec["servers"])

    def test_adds_path_and_method(self, sample_http_flow):
        extractor = APISpecExtractor()
        extractor.response(sample_http_flow)
        assert "/v1/users" in extractor._spec["paths"]
        assert "get" in extractor._spec["paths"]["/v1/users"]

    def test_infers_response_schema(self, sample_http_flow):
        extractor = APISpecExtractor()
        extractor.response(sample_http_flow)
        op = extractor._spec["paths"]["/v1/users"]["get"]
        assert "200" in op["responses"]

    def test_schema_inference_dict(self):
        extractor = APISpecExtractor()
        schema = extractor._infer_schema({"name": "Alice", "age": 30})
        assert schema["type"] == "object"
        assert schema["properties"]["name"]["type"] == "string"
        assert schema["properties"]["age"]["type"] == "integer"

    def test_schema_inference_list(self):
        extractor = APISpecExtractor()
        schema = extractor._infer_schema([{"id": 1}])
        assert schema["type"] == "array"
        assert schema["items"]["type"] == "object"

    def test_export_writes_json_without_yaml(self, tmp_path, monkeypatch):
        """When pyyaml is absent, extractor falls back to JSON."""
        import builtins

        real_import = builtins.__import__

        def mock_import(name, *args, **kwargs):
            if name == "yaml":
                raise ImportError("mocked: yaml not available")
            return real_import(name, *args, **kwargs)

        extractor = APISpecExtractor()
        extractor._output_file = tmp_path / "spec.yaml"
        extractor._spec["paths"]["/test"] = {
            "get": {"responses": {"200": {"description": "ok"}}},
        }

        monkeypatch.setattr(builtins, "__import__", mock_import)
        extractor._write_spec()

        fallback = tmp_path / "spec.json"
        assert fallback.exists()
        data = json.loads(fallback.read_text())
        assert "paths" in data
