"""Abstract base class for all mitmrouter addons."""
from __future__ import annotations

import abc
import logging
from typing import Any

from mitmproxy import http

logger = logging.getLogger(__name__)


class AbstractAddon(abc.ABC):
    """Base class every addon must inherit from.

    Subclasses must:
    - Declare ``__addon_manifest__`` at module level.
    - Implement at least one mitmproxy event hook.
    """

    # ------------------------------------------------------------------ #
    # mitmproxy lifecycle hooks (all optional unless stated otherwise)    #
    # ------------------------------------------------------------------ #

    def load(self, loader: Any) -> None:  # noqa: ANN401
        """Declare options and CLI commands at startup."""

    def configure(self, updated: set[str]) -> None:
        """React to option changes."""

    def running(self) -> None:
        """Called once the proxy is fully running."""

    def request(self, flow: http.HTTPFlow) -> None:  # noqa: ARG002
        """Intercept an HTTP request."""

    def response(self, flow: http.HTTPFlow) -> None:  # noqa: ARG002
        """Intercept an HTTP response."""

    def error(self, flow: http.HTTPFlow) -> None:  # noqa: ARG002
        """Handle a flow error."""

    def shutdown(self) -> None:
        """Flush buffers and clean up on shutdown."""

    # ------------------------------------------------------------------ #
    # Health-check API                                                    #
    # ------------------------------------------------------------------ #

    def health_check(self) -> dict[str, Any]:  # noqa: ANN401
        """Return a dict describing this addon's health.

        Implementations should return::

            {"status": "healthy", "details": {...}}
        """
        return {"status": "healthy"}

    # ------------------------------------------------------------------ #
    # Helpers                                                             #
    # ------------------------------------------------------------------ #

    @classmethod
    def manifest(cls) -> dict[str, Any]:  # noqa: ANN401
        """Return the addon manifest declared in the module."""
        import sys
        mod = sys.modules.get(cls.__module__)
        if mod and hasattr(mod, "__addon_manifest__"):
            return mod.__addon_manifest__
        raise AttributeError(
            f"Module {cls.__module__!r} does not declare __addon_manifest__"
        )
