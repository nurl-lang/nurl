# Changelog

## 1.0.7

- Requires `http ^0` instead of `^0.3`. http has been 0.4.0 since #1014
  and 0.4.0 is what this package is built and tested against in the
  repo, but the manifest still asked for `^0.3` — so an install from the
  registry resolved http 0.3.2 and compiled against different code than
  anything here was tested on. `nurlpkg publish` refuses on exactly that
  mismatch, which is how it surfaced. The caret sits on the major so a
  0.x minor release of http cannot silently re-open the same gap in
  every consumer.

## 1.0.6

- Internal rename, no API change: `_wh_is_ggml` was `__`-private to
  `src/main.nu` and called from `src/serve.nu`. A `__` name is
  file-scoped, so that call went through the compiler's obsolete
  cross-file compatibility path and warned on every build. It now
  carries the single-underscore shared-internal spelling.
