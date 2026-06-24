# tls — a pure-NURL TLS 1.3 client

A TLS 1.3 client (RFC 8446) written entirely in NURL, with **no OpenSSL
and no FFI beyond the libc TCP socket**. Every cryptographic primitive —
the handshake, the record layer, **and full certificate verification** —
is implemented from scratch in pure NURL, so an authenticated, encrypted
connection works on a machine that has nothing installed: Linux, macOS,
the BSDs, Windows.

It prefers TLS 1.3 (`TLS_AES_128_GCM_SHA256` / `TLS_CHACHA20_POLY1305_SHA256`)
and **falls back to TLS 1.2** (the ECDHE-RSA / ECDHE-ECDSA AES-128-GCM and
ChaCha20-Poly1305 suites) when the server doesn't offer 1.3 — all over the
X25519 key-exchange group. Between them this reaches essentially every
HTTPS server in use.

## What's implemented

* **Key exchange** — X25519 (RFC 7748), constant-time Montgomery ladder.
* **Record protection** — ChaCha20-Poly1305 AEAD (RFC 8439) and
  AES-128-GCM (NIST SP 800-38D), negotiated per the server's choice.
* **Key schedule** — HKDF-Extract/Expand + HKDF-Expand-Label / Derive-Secret
  (RFC 5869, RFC 8446 §7.1) over pure HMAC-SHA-256.
* **Handshake** — ClientHello (SNI, supported_versions, supported_groups,
  signature_algorithms, key_share), ServerHello parsing, the full
  handshake/application key schedule, decryption of the server flight,
  verification of the server Finished MAC, and the client Finished.
* **Certificate verification (verify-full, the default)** —
  * the server's **CertificateVerify** signature over the handshake
    transcript;
  * the presented **certificate chain** (each cert signed by the next);
  * an **anchor** in the system trust store (matched by trusted
    subject+key, or by issuer with a verified signature);
  * the **validity window** (notBefore/notAfter);
  * **hostname** matching against the leaf SANs (RFC 6125 `*.` wildcards).
  * Signature algorithms: RSA PKCS#1 v1.5 (SHA-256/384/512), RSA-PSS
    (SHA-256), ECDSA P-256/SHA-256 and P-384/SHA-384 — the algorithms used
    by essentially all real RSA and ECDSA certificate chains.
* **Application data** — encrypted `tls_write` / `tls_read`.

Every crypto primitive is validated against its RFC's published
known-answer vectors (`x25519_vectors`, `chacha20poly1305_vectors`,
`hkdf_vectors`, `rsa_verify`, `ecdsa_p256_verify`, `x509_parse`). The
end-to-end client has been verified against OpenSSL and, with full
certificate verification, against live `example.com` and `cloudflare.com`
(accepted) and self-signed / wrong-hostname cases (rejected).

## API

```
( tls_connect host port server_name )          → !*TlsConn TlsErr  // verify-full
( tls_connect_insecure host port server_name ) → !*TlsConn TlsErr  // no cert check
( tls_write conn ( Vec u ) bytes )             → !v TlsErr
( tls_read conn max )                          → !( Vec u ) TlsErr // [] at EOF
( tls_close conn )                             → v
```

`tls_connect` is secure by default: it fails with `TlsBadCert` unless the
chain verifies. `tls_connect_insecure` skips verification (pinned /
self-signed / testing only) — encrypted but not authenticated.

## Limitations

* TLS 1.3 and 1.2 only (no SSLv3 / TLS 1.0 / 1.1 — long obsolete).
* ECDHE key exchange over X25519 only (no static-RSA or P-256/P-384 ECDHE).
* No client certificates, no session resumption / 0-RTT, no OCSP / CRL
  revocation checking. Ed25519 and P-521 certificate signatures are not
  yet verified (rare in practice).

## Demo

Built like any registry package, from the package directory (its own
modules are imported as `src/…`, the stdlib via `$NURL_STDLIB`):

```
cd packages/tls
nurlc src/https_get.nu > https_get.ll && cc -O2 -flto https_get.ll "$NURL_STDLIB/stdlib/runtime.o" -lm -lpthread -lssl -lcrypto -o https_get
./https_get example.com 443 /
```
