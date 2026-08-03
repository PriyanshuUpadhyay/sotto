# Sotto — agent instructions

## Cleanup after finishing work
- Remove any ad-hoc build/test artifacts you created once done: one-off derived-data dirs (`.local-build-test`, `.test-build`, custom `-derivedDataPath` targets), stale `~/Library/Developer/Xcode/DerivedData/Sotto-*` caches, and any temp/scratch data from the session.
- Do NOT delete `.local-build` — it is the live `make local` incremental cache.
- Prefer pointing test runs at the scratchpad or `.local-build-test`, then delete it when done.
