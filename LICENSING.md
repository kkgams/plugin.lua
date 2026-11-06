## Current tag-based release authorization

Pushing the matching version tag authorizes release in this repository. No manual
checksum variables, approval boolean, hosted-review approval, or `release`-branch
HEAD match is required. Branch candidates still validate their payloads; they do
not publish a GitHub Release or OCI version. Manual branch runs verify only.

Repository/tag/version and WIT identity checks, build/runtime tests, source and
build-evidence checks, nonempty LICENSE/NOTICE, exact embedded licensing bytes,
generated SHA256SUMS, independent candidates, and GitHub Release/OCI no-overwrite
checks remain required. The workflow uses the automatic GitHub token. Never move
or overwrite an existing version tag. Pages publication remains independent.

This policy supersedes historical approval-variable and pre-tag review/branch
requirements below, not source provenance or legal terms. It does not claim hosted
validation or authorize this editing session to commit, push, tag, or publish.
No source snapshots, legal texts, or historical evidence are refreshed.

> Prepared target: `plugin.lua` v0.2.1; not yet published.
> The documentation below is a frozen historical record, not current
> pending approval requirements. Its manual approval/checksum and pre-tag
> review/branch requirements are superseded above; content checks remain.

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
