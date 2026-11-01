### Fixed

- **A `NURL_SAN=1` build no longer overflows a fiber on input its normal
  build handles** (Agora #319). A fiber's stack was 64 KB in every build.
  Under AddressSanitizer each frame carries redzones and instrumented
  locals, so a JSON document at JSON_MAX_DEPTH crashed a fiber with a
  stack-overflow at -O2 (nurl.sh's default) and at -O0. Sanitized builds
  now give each fiber 256 KB, in the hosted runtime and the bare one.
  Normal builds keep 64 KB, so their memory use and speed are unchanged.
  The sanitizer CI job builds json_deep_fiber with `NURL_SAN=1` at -O2 and
  -O0; the sanitizer corpus compiles at -O1, where the overflow didn't
  show.
