# Licensing and publication gate — plugin.lua

The repository owner approved Apache-2.0 for **GAMS-authored** code in
`plugin.lua`. Root `LICENSE` is the complete Apache-2.0 text. This choice
does not relicense vendored, linked, generated, or third-party source.

Root `NOTICE` and `THIRD-PARTY-REVIEW.md` are repository-specific engineering
inventory proposals, **not** owner approval of those third-party texts or
provenance. Review all linked WASI SDK objects, WIT packages, generated
bindings and component adapters for this exact plugin. See the review document
for unresolved provenance and runtime-test gates. Build-only npm/Nix inputs
are not included in the raw WASM notices; if distributing their source or JS
outputs, audit them separately.

**Do not push source to the public repository or distribute an Actions artifact
until the owner has reviewed and accepted this repository's exact NOTICE and
third-party provenance.** A source push itself can redistribute vendor code.
After review, the owner may set only this repository's `LICENSE_SHA256` and
`NOTICE_SHA256` Actions variables to the exact lowercase SHA-256 values of its
root files. The branch upload and tag workflows fail closed if either digest
or embedded byte sequence differs. A successful local build is not approval.
