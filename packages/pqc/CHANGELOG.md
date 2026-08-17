# Changelog

All notable changes to `pqc` are documented here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-08-17

### Added

- ML-KEM (FIPS 203) at all three parameter sets — 512, 768 and 1024 —
  built on `stdlib/std/mlkem.nu`, in pure NURL with no libcrypto and no
  liboqs.
- `keygen`, `encaps` and `decaps`. The parameter set is inferred from
  the key length on `encaps`/`decaps`, since the three sizes are
  distinct.
- `probe HOST...` — completes a real TLS 1.3 handshake and reports the
  key-exchange group the server selected, so you can tell a genuine
  `X25519MLKEM768` negotiation from a silent fallback to X25519.
- `bench` — keygen/encaps/decaps throughput on the current machine.
- `kat` — self-test against NIST ACVP key-generation vectors, plus a
  round trip and the implicit-rejection path at every parameter set.
