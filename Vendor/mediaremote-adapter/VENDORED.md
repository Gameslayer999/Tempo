# Vendored: mediaremote-adapter

Upstream: https://github.com/ungive/mediaremote-adapter
License: BSD 3-Clause (see LICENSE)
Pinned commit: see COMMIT

## Why it is here

Since macOS 15.4 the private MediaRemote framework only answers processes that
carry Apple's entitlement for it. This adapter is loaded inside `/usr/bin/perl`
— an Apple-signed, entitled binary — by `bin/mediaremote-adapter.pl`, which
`dlopen`s the built framework and calls its `adapter_*` symbols. That is how
Tempo reads now-playing state for players it has no AppleScript dictionary for.

Built by `scripts/build-media-adapter.sh` into `Vendor/build/`.

## Local modifications

- `src/adapter/test.m` and `src/test/` removed. They implement the `test` CLI
  command, which requires the separate `MediaRemoteAdapterTestClient`
  executable that Tempo does not ship. `scripts/build-media-adapter.sh`
  verifies entitlement by running the real `get` command instead, which
  exercises the same code path Tempo actually depends on.

Nothing else is modified. Re-vendoring means copying `src/`, `include/`,
`bin/`, `LICENSE` and `README.md` from upstream and re-applying the removal
above.
