# ADR-002: Sigstore for Release Signing over GPG

## Status

Accepted (2024-06)

## Context

Phase 1 introduced `release.yml` with a placeholder for artifact
signing.  We evaluated two approaches for signing release artifacts
(Python wheels, source tarballs):

1. **GPG** (GNU Privacy Guard) – traditional, widely understood, but
   requires long‑term key management, revocation infrastructure, and
   manual key distribution.
2. **Sigstore** – a modern, certificate‑transparency‑backed signing
   ecosystem that binds signatures to OIDC identities with short‑lived
   ephemeral keys.  No key management burden.

## Decision

We will use **Sigstore** (`sigstore-python`) for signing release
artifacts.

Rationale:

- Sigstore signatures are **keyless** from the signer's perspective;
  the private key is generated and discarded in‑memory during signing.
- Verification uses the public transparency log (Rekor) and the signer's
  OIDC identity (e.g., GitHub Actions workflow identity), eliminating
  the "which public key do I trust?" problem.
- The `sigstore-python` CLI integrates cleanly into GitHub Actions with
  `id-token: write` permissions.
- The Python Package Index (PyPI) is actively adopting Sigstore‑based
  attestations, aligning with the broader ecosystem direction.

We explicitly rejected GPG because:

- GPG key distribution is a persistent operational burden.
- Revocation is unreliable in practice.
- The UX for verifying GPG signatures is poor compared to `cosign verify-blob`.

## Consequences

- **Positive:** Zero‑touch signing in CI.  Verifiable provenance
  through the Sigstore transparency log.  No secrets to rotate.
- **Negative:** Sigstore is newer; some downstream consumers may not
  have adopted verification tooling yet.  The OIDC dependency means
  local developer signing requires an OIDC provider (e.g.,
  `sigstore sign --oidc-client-id`).
- **Mitigation:** We provide both Sigstore signatures and SHA‑256
  checksums in the release.  Documentation in `SECURITY.md` explains
  how to verify both.