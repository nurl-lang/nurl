### Added

- **ECDSA P-256 has the gates its fixed-base comb was waiting for**
  (Agora #86). `compiler/tests/ecdsa_p256_wycheproof`: all 262 ECDSA
  P-256 / SHA-256 cases of Project Wycheproof in P1363 form (173 valid, 89
  invalid: arithmetic edges of GF(n) and GF(p), special-case digests,
  edge-case public keys, point duplication, range checks, signature size).
  `ecdsa_p256_sign_vectors`: sign-then-verify over 48 keys — 1, 2, 3, the
  Booth-digit edges 15‥17 and 31‥33, n − 1, n − 2, (n ± 1)/2, 2^255, 2^128 ± 1,
  bit patterns, then pseudo-random ones — each public key and signature
  equal byte for byte to an independent RFC 6979 signer's (checked against
  RFC 6979 A.2.5, every signature verified by OpenSSL), each verifying, and
  each rejected with one bit of s flipped. `ecdsa_p256_verify_edges`: 19
  signatures whose public key is solved so that the verify pass's mixed
  addition meets the accumulator EQUAL to the table entry (the doubling
  case) or its NEGATION (the sum is ∞), on the u1·G and the u2·Q addition,
  at the first, middle and last windows. Random signatures reach those
  branches with probability ~2^-256 and Wycheproof's cases miss them in
  this window layout; a verify that turned either branch into the other
  passed every earlier test and fails 9 or 10 of these.
