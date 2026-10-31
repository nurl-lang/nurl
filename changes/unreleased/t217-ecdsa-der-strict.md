### Security

- **An ECDSA signature has exactly one accepted DER encoding** (Agora #217).
  Three decoders read the ECDSA-Sig-Value in front of `ecdsa_p256_verify`
  and `ecdsa_p384_verify`:
  - TLS CertificateVerify and X.509 chain checks (`std/tls_verify`)
  - `x509_ecdsa_sig_rs` (`std/x509_gen`, used by the PKI server)
  - CSR self-signatures (`std/csr`)

  Each of them also accepted encodings that strict DER refuses:
  - bytes after the SEQUENCE, or after s inside it
  - BER long-form or zero-padded lengths
  - a wrong tag
  - a negative INTEGER, or one with a superfluous leading zero

  So one signature had many encodings. This is malleability, not forgery:
  the r and s that came out still had to verify. Of Wycheproof's 310
  invalid DER cases, the TLS decoder accepted 35 and the x509_gen one 28.
  All three now call one strict decoder, `der_ecdsa_sig_rs` in
  `std/x509`. It accepts exactly `SEQUENCE { INTEGER r, INTEGER s }` in
  minimal DER with nothing after it. New gates:
  `compiler/tests/ecdsa_p256_wycheproof_der` and
  `ecdsa_p384_wycheproof_der` run all of Wycheproof's ECDSA DER cases
  through the decoder and verify: 484 for P-256 / SHA-256 and 504 for
  P-384 / SHA-384.
