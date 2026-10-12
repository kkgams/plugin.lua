## Current 0.2.1 release authorization

The owner's current instruction is: "no need for review of checksums / licenses - those area already prepared - drop pending reviews, commit changes, prepare tags - create script (using gh) to push to repos and create releases."

This supersedes earlier pending human checksum/license and hosted-review approvals
for the prepared 0.2.1 release. Documentation commits and annotated **local**
`v0.2.1` tags at the tested HEAD are authorized. No repeated human review is
pending for these unchanged prepared bytes. Prior "before any tag" restrictions,
including publisher migration, do not restrict local tagging.

This is not evidence of hosted Linux CI, GUI/Host consumption, registry visibility,
immutable policy, draft-first rehearsal or anonymous public-byte verification.
Those coverage gaps remain accurately unverified; publication technical checks
still apply. Version, source closure, evidence, exact license/notice digest and
candidate-byte gates remain strict. No source or legal evidence is refreshed.
No remote push/publication, repository variable or remote configuration change
is performed by this local preparation. Never move or overwrite an existing tag.

> Prepared target: `plugin.lua` v0.2.1; not yet published.
> The documentation below is a frozen historical record, not current
> pending approval requirements. Its human review/local-tag restrictions are
> superseded above; technical publication safeguards are not waived.

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
