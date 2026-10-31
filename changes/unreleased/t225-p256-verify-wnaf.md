### Performance

- **ECDSA P-256 verify is about 11 % faster** (Agora #225): 89 → 79 µs
  on a Cascade Lake class Xeon. The verify pass still shares its 256
  doublings between u1·G and u2·Q, but it now adds along each scalar's
  width-w NAF instead of its 4-bit windows:
  - u1 uses width 7 against 1·G … 127·G, built once per process.
  - u2 uses width 5 against 1·Q … 15·Q, built per verify from one
    doubling, seven additions and one batch inversion.

  A width-w NAF has a non-zero digit about once every w + 1 positions, so
  a verify makes about 32 + 43 point additions instead of about 120. It
  also no longer needs a field inversion at the end: x(R) ≡ r (mod n) is
  checked as X = r·Z², or (r + n)·Z² when r + n < p.
  `compiler/tests/ecdsa_p256_verify_edges` is rebuilt for the new layout:
  its 12 solved signatures drive `_p256_jmadd_vt`'s acc = entry and
  acc = −entry branches on both the G and the Q additions, early in the
  pass, in the middle and at the last addition. Either branch mutated
  into the other fails 6 of them, while all 262 Wycheproof cases still
  pass with that mutation.
