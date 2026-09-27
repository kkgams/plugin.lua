# Publishing plugin.lua — NOT READY

No owner-approved LICENSE or NOTICE exists in this extraction. This scaffold does
not grant a license, approve third-party notices, or authorize publication.
Lua runtime E2E is still blocked (jco rejects the exception-handling core); provide an independent component-model host. Review vendored Lua and jsmn provenance and notices.

`make test` builds/tests without licensing texts. `make release-candidate` runs
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

## Owner-operated sequence (only after all blockers above are resolved)

1. Review the final linked artifact inventory and exact LICENSE/NOTICE bytes;
   remove/update the no-license warning in LICENSING.md only after approval.
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
   For Lua, this job must first pass the independent runtime E2E gate; branch
   `verify.yml`'s static test is not enough.
5. Only when the branch candidate and hosted release-shell run have passed,
   check that `v$(cat version.txt)` has never been pushed, then tag exactly that
   verified commit and push **only that immutable tag**:

   ```sh
   git tag -a "v$(cat version.txt)" -m "plugin.lua $(cat version.txt)"
   git push origin "v$(cat version.txt)"
   ```

   Review the GitHub Release assets and GHCR raw WASM anonymously afterward.
   If a pushed tag fails, fix the branch and use a new version; never retag.
