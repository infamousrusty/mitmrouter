# ADR-003: Addon Manifest Schema

## Status

Accepted (2024-06)

## Context

Every addon exposes a `manifest()` classmethod that returns a
dictionary describing the addon's metadata.  We needed a consistent
schema so that:

- The `AddonRegistry` can validate addons at discovery time.
- CLI tools (`mitmrouter --list-addons --json`) produce predictable output.
- Users and automated tooling can reason about addon compatibility.

## Decision

The manifest dictionary adheres to this schema (all fields required
unless noted):

| Field           | Type           | Description                                      |
|-----------------|----------------|--------------------------------------------------|
| `name`          | `string`       | Unique addon identifier (e.g. `"json_traffic_logger"`). |
| `description`   | `string`       | One‑sentence human‑readable description.         |
| `category`      | `string`       | One of `mitmproxy_native`, `external_tools`, `reporting`. |
| `version`       | `string`       | SemVer string (e.g. `"1.2.0"`).                  |
| `min_mitmproxy` | `string`       | Minimum mitmproxy version required (SemVer).     |
| `outputs`       | `list[string]` | Glob patterns for files this addon produces.     |
| `consumes`      | `list[string]` | (Optional) Glob patterns for files this addon reads. |

Example:

```python
{
    "name": "inventory_tracker",
    "description": "Build a structured inventory of observed HTTP endpoints.",
    "category": "mitmproxy_native",
    "version": "1.0.0",
    "min_mitmproxy": "10.3.0",
    "outputs": ["inventory_*.json"],
    "consumes": [],
}
We deliberately kept the schema flat (no nested objects) to
simplify validation and serialisation. If future needs demand richer
metadata (e.g., author, license, config schema), those can be added as
optional fields in a backward‑compatible manner.

Consequences
Positive: Uniform addon metadata enables automated documentation
generation, compatibility checks, and discoverability. The flat
structure is easy to validate with a simple assert‑based checker.
Negative: The flat schema may become limiting; optional fields
may proliferate over time.
Mitigation: We will version the manifest schema independently
(via a manifest_version field) if breaking changes are needed.


---

## File 12: `docs/adr/ADR-004-three-tier-addon-categories.md` (M2.1-C)

```markdown
# ADR-004: Three‑Tier Addon Categories

## Status

Accepted (2024-06)

## Context

The addon ecosystem needed a clear taxonomy so users could understand
how each addon interacts with mitmproxy and external tooling.  Without
categories, addons would be a flat, undifferentiated list, making
discovery and profile construction difficult.

We identified three distinct operational modes:

1. Addons that hook directly into mitmproxy's event loop and write
   structured data to disk.
2. Addons that spawn external, long‑running processes (e.g., Zeek,
   Suricata) and feed them traffic.
3. Addons that consume the output of other addons to produce reports.

## Decision

We defined **three categories**:

| Category           | Description                                              |
|--------------------|----------------------------------------------------------|
| `mitmproxy_native` | Runs inside mitmproxy; uses hooks like `request`, `response`, `tls_established`. Produces JSON/YAML artefacts. |
| `external_tools`   | Spawns or communicates with an external tool process.  Configures and manages the tool lifecycle. |
| `reporting`        | Post‑processing addons that read artefacts from other addons and generate reports (HTML, Markdown, PDF). |

Each addon declares its category in its `manifest()` and via the
`category` property on the class.

## Consequences

- **Positive:** Clear separation of concerns.  Profiles can
  independently enable/disable categories.  Users understand the
  runtime cost model (native = low overhead, external = process spawn,
  reporting = post‑hoc).
- **Negative:** Some addons may straddle categories (e.g., an addon
  that both captures traffic *and* spawns an external analyser).  The
  rigid taxonomy forces a choice.
- **Mitigation:** If an addon truly spans categories, we recommend
  splitting it into two addons (one native, one external) that share a
  configuration contract.  The `reporting` category is explicitly
  post‑hoc and runs at shutdown, avoiding lifecycle conflicts.