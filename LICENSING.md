# Licensing and publication gate — plugin.lua

The repository owner approved Apache-2.0 for **GAMS-authored** code in
`plugin.lua`. Root `LICENSE` is the complete Apache-2.0 text. This choice
does not relicense vendored, linked, generated, or third-party source.

The owner also reviewed this repository's separate `NOTICE` and linked-code
inventory in `THIRD-PARTY-REVIEW.md`. For respack, the owner identified the
Odin jsmn file as a port of Serge Zaitsev's MIT jsmn and approved retaining
its original license text alongside Apache-2.0 terms for GAMS-authored
changes. Build-only npm/Nix inputs are not included in raw-WASM notices;
distributing their source or JS outputs requires separate review.

The owner may set **this repository's** `LICENSE_SHA256` and `NOTICE_SHA256`
Actions variables to the exact lowercase SHA-256 values of its reviewed root
files, then push `release`. A branch CI candidate is distribution: the upload
and tag workflows fail closed if either digest or embedded byte sequence
differs. Inspect the hosted Linux candidate and link evidence; a successful
local build alone does not authorize a version tag. The owner-pushed matching
tag is the release decision only after the branch candidate and release-shell
rehearsal pass on that commit.
