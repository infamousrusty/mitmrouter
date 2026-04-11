"""Addon discovery, loading, and validation registry."""

from __future__ import annotations

import importlib
import logging
from pathlib import Path
from typing import Any

logger = logging.getLogger(__name__)

_ADDON_CATEGORIES = ("mitmproxy_native", "external_tools", "reporting")


class AddonRegistry:
    """Discover and manage available addons."""

    def __init__(self, addons_dir: Path | None = None) -> None:
        self.addons_dir = addons_dir or (Path(__file__).parent.parent)
        self.registry: dict[str, dict[str, Any]] = {}

    # ------------------------------------------------------------------ #
    # Discovery                                                           #
    # ------------------------------------------------------------------ #

    def discover(self) -> None:
        """Scan addon sub-packages and register manifests."""
        for category in _ADDON_CATEGORIES:
            category_path = self.addons_dir / category
            if not category_path.is_dir():
                continue
            for addon_file in sorted(category_path.glob("*.py")):
                if addon_file.name.startswith("_"):
                    continue
                self._load_module(category, addon_file)

    def _load_module(self, category: str, addon_file: Path) -> None:
        module_name = f"addons.{category}.{addon_file.stem}"
        try:
            module = importlib.import_module(module_name)
        except Exception:  # noqa: BLE001
            logger.exception("Failed to import %s", module_name)
            return

        manifest = getattr(module, "__addon_manifest__", None)
        if manifest is None:
            logger.debug("No manifest in %s – skipping", module_name)
            return

        name = manifest.get("name")
        if not name:
            logger.warning("Manifest missing 'name' in %s", module_name)
            return

        self.registry[name] = {
            "module": module,
            "manifest": manifest,
            "category": category,
        }
        logger.debug("Registered addon: %s (%s)", name, category)

    # ------------------------------------------------------------------ #
    # Retrieval                                                           #
    # ------------------------------------------------------------------ #

    def get_instance(self, name: str) -> Any:  # noqa: ANN401
        """Instantiate and return an addon by name."""
        if name not in self.registry:
            raise KeyError(f"Addon {name!r} not found in registry")
        entry = self.registry[name]
        manifest = entry["manifest"]
        addon_cls = getattr(entry["module"], manifest["class_name"], None)
        if addon_cls is None:
            raise AttributeError(
                f"Addon module for {name!r} does not expose class "
                f"{manifest['class_name']!r}"
            )
        return addon_cls()

    def list_addons(
        self,
        *,
        category: str | None = None,
        footprint: str | None = None,
        ci_bundled: bool | None = None,
    ) -> list[dict[str, Any]]:
        """Return a filtered list of addon summaries."""
        results = []
        for name, entry in self.registry.items():
            m = entry["manifest"]
            if category and entry["category"] != category:
                continue
            if footprint and m.get("test_footprint") != footprint:
                continue
            if ci_bundled is not None and m.get("ci_bundled") != ci_bundled:
                continue
            results.append(
                {
                    "name": name,
                    "version": m.get("version"),
                    "category": entry["category"],
                    "description": m.get("description"),
                    "ci_bundled": m.get("ci_bundled", False),
                    "test_footprint": m.get("test_footprint", "medium"),
                    "external_tool": m.get("external_tool_integration"),
                }
            )
        return results

    # ------------------------------------------------------------------ #
    # Validation                                                          #
    # ------------------------------------------------------------------ #

    def validate(self, name: str) -> tuple[bool, str]:
        """Validate an addon's manifest and Python dependencies."""
        if name not in self.registry:
            return False, f"Addon {name!r} not registered"
        manifest = self.registry[name]["manifest"]

        # Required manifest fields
        for field in ("name", "version", "description", "dependencies"):
            if field not in manifest:
                return False, f"Missing required manifest field: {field!r}"

        # Python dependency check
        for dep in manifest["dependencies"].get("python", []):
            try:
                importlib.import_module(dep)
            except ImportError:
                return False, f"Missing Python dependency: {dep!r}"

        return True, "OK"
