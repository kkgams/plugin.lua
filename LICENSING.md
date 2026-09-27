# Licensing status

**Do not publish or release this repository.** The repository owner's approval of
the license for the GAMS-authored source is unresolved. No license is granted by
this extraction, and no `LICENSE` file is supplied or implied.

Before publication, the owner must choose and approve a license, apply it to the
GAMS-authored files, and review the complete linked and vendored third-party
inventory. That inventory must cover the local WIT packages, generated bindings,
the WASI SDK/toolchain runtime objects, and every source file linked into the WASM
artifact. Component-specific vendored sources (notably Lua and jsmn-derived code)
need provenance, license-text, notice, and redistribution review. Build-tool npm
and Nix closures also require the appropriate source-distribution review.

The verification workflow builds and tests without licensing approval. Its
optional candidate upload and the separate release workflow fail closed on exact
owner-reviewed LICENSE/NOTICE digests. See PUBLISHING.md; no approval exists yet.
