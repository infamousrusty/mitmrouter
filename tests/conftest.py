"""Shared pytest fixtures for mitmrouter addon tests."""

from __future__ import annotations

from collections.abc import Generator
from typing import Any

import pytest
from mitmproxy import http
from mitmproxy.test import taddons
from mitmproxy.test import tflow


# ------------------------------------------------------------------ #
# Flow fixtures                                                       #
# ------------------------------------------------------------------ #


@pytest.fixture
def sample_http_flow() -> http.HTTPFlow:
    """A basic HTTP GET flow."""
    flow = tflow.tflow(resp=tflow.tresp())
    flow.request.host = "api.example.com"
    flow.request.path = "/v1/users"
    flow.request.method = "GET"
    flow.request.scheme = "http"
    flow.response.status_code = 200
    flow.response.headers["content-type"] = "application/json"
    flow.response.content = b'{"id": 1, "name": "Alice"}'
    return flow


@pytest.fixture
def sample_post_flow() -> http.HTTPFlow:
    """A POST flow with JSON body."""
    flow = tflow.tflow(resp=tflow.tresp())
    flow.request.host = "api.example.com"
    flow.request.path = "/v1/users"
    flow.request.method = "POST"
    flow.request.scheme = "http"
    flow.request.headers["content-type"] = "application/json"
    flow.request.content = b'{"name": "Bob", "email": "bob@example.com"}'
    flow.response.status_code = 201
    flow.response.headers["content-type"] = "application/json"
    flow.response.content = b'{"id": 2, "name": "Bob"}'
    return flow


@pytest.fixture
def https_flow() -> http.HTTPFlow:
    """An HTTPS flow (TLS established)."""
    flow = tflow.tflow(resp=tflow.tresp())
    flow.request.host = "secure.example.com"
    flow.request.path = "/api/v2/data"
    flow.request.method = "GET"
    flow.request.scheme = "https"
    flow.server_conn.tls_established = True
    flow.response.status_code = 200
    return flow


# ------------------------------------------------------------------ #
# Addon context fixture                                               #
# ------------------------------------------------------------------ #


@pytest.fixture
def addon_ctx() -> Generator[Any, None, None]:
    """Provide a mitmproxy taddons.context() for integration tests."""
    with taddons.context() as tctx:
        yield tctx
