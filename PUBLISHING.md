> **Prospective v0.2.0 maintenance preparation — NOT release-ready.**
> Target: `plugin.lua` v0.2.0, `plugin.lua.wasm`, `ghcr.io/kkgams/gams/lua:0.2.0`.
> Below is frozen historical documentation: existing GitHub Release URLs,
> versioned examples and repair instructions refer to their original releases.
> For a future v0.2.0 candidate, use the prepared distribution metadata;
> rebuild and run repository-owned locked toolchain/runtime tests, review
> source drift, linked evidence and exact LICENSE/NOTICE/candidate digests.
> Migrate the direct-release publisher to draft-first immutable-policy and
> exact public-byte verification before any tag/OCI push/Pages publication.
> Do not run the historical publishing commands as v0.2.0 instructions.

# Publishing plugin.lua — hosted review pending

The owner approved Apache-2.0 for this repository's GAMS-authored code and
reviewed its separate third-party NOTICE. A pushed matching tag is **not**
authorized by that review alone: first verify the exact Linux candidate and
release-shell rehearsal from the same `release` branch commit.
The final candidate must pass the standalone Wasmtime E2E on hosted Linux.

`make test` builds/tests without requiring licensing texts. `make release-candidate` runs
those tests, then checks nonempty root LICENSE and NOTICE against this repository's
owner-set `LICENSE_SHA256` and `NOTICE_SHA256` variables (lowercase SHA-256),
embeds their exact bytes as `gams.license` and `gams.notice`, verifies them,
and stages a checksummed candidate. Changing either text requires renewed review
and updated digests. There is no approval boolean.

Branch CI without both digests still tests but does not upload binaries. A branch
with both digests fails closed if either text is missing or mismatched. Manual
release workflow dispatch on a branch verifies but never uploads or publishes.
The matching `v` tag from `version.txt` in `kkgams/plugin.lua`
triggers release only **after** owner review of the hosted Linux build and the
exact downloaded candidate. Never push a tag before that review; do not move a
failed tag. Tagged jobs fail before building when licensing is missing. Publication
rechecks digests and candidate bytes, requires the tag's commit to be the
current `release` branch head, refuses an existing GitHub Release, and refuses
to replace different bytes at the OCI tag. The OCI artifact is raw WASM,
not a package of licensing files; the GitHub Release includes LICENSE, NOTICE
and SHA256SUMS. Verify GHCR package permissions/visibility before tagging.

## Owner-operated sequence

1. Confirm the exact LICENSE/NOTICE bytes and linked inventory recorded in
   THIRD-PARTY-REVIEW.md and LICENSING.md before setting digest variables.
2. Set **repository-scoped Actions variables**, not secrets, independently for
   `kkgams/plugin.lua` (never copy another Unit's digests):

   ```sh
   gh variable set LICENSE_SHA256 -R kkgams/plugin.lua --body "$(shasum -a 256 LICENSE | cut -d ' ' -f 1)"
   gh variable set NOTICE_SHA256 -R kkgams/plugin.lua --body "$(shasum -a 256 NOTICE | cut -d ' ' -f 1)"
   ```

   The ephemeral `GITHUB_TOKEN` is provided by Actions; no personal token or
   other GitHub secret is requested by the workflow. A local release-candidate
   dry run needs `APPROVED_LICENSE_SHA256` and `APPROVED_NOTICE_SHA256` in its
   process environment with those same digests; CI maps the repository vars.
3. Push the reviewed `release` branch: `git push -u origin release`. Inspect
   `verify.yml` on GitHub for that exact commit, download its branch candidate,
   verify `SHA256SUMS` and embedded notice bytes, and review hosted Linux evidence.
   **A green build alone is not enough**: confirm the candidate was uploaded.
4. Manually run `release.yml` **on the branch** to exercise its release shell
   without publishing: `gh workflow run release.yml -R kkgams/plugin.lua --ref release`.
   For Lua, **both the branch candidate and this rehearsal** require the
   independent runtime E2E script; `make test`'s static checks are not enough.
5. Only when the branch candidate and hosted release-shell run have passed,
   check that `v$(cat version.txt)` has never been pushed, then tag exactly that
   verified commit and push **only that immutable tag**:

   ```sh
   git tag -a "v$(cat version.txt)" -m "plugin.lua $(cat version.txt)"
   git push origin "v$(cat version.txt)"
   ```

   The tag workflow verifies the tag points to the current `release` head but
   cannot know whether the owner inspected the prior candidate and rehearsal;
   **pushing the tag is the owner's explicit release decision** after those
   checks. Review the GitHub Release assets and GHCR raw WASM anonymously.
   If a pushed tag fails, fix the branch and use a new version; never retag.
