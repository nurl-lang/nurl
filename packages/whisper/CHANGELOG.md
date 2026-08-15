# Changelog

## 1.0.6

- Internal rename, no API change: `_wh_is_ggml` was `__`-private to
  `src/main.nu` and called from `src/serve.nu`. A `__` name is
  file-scoped, so that call went through the compiler's obsolete
  cross-file compatibility path and warned on every build. It now
  carries the single-underscore shared-internal spelling.
