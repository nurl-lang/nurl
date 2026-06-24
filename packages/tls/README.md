# tls — a pure-NURL TLS 1.3 client

A TLS 1.3 client (RFC 8446) written entirely in NURL, with **no OpenSSL
and no FFI beyond the libc TCP socket**. Every cryptographic primitive in
the handshake and record layer is implemented from scratch in pure NURL,
so an encrypted connection works on a machine that has nothing installed
— Linux, macOS, the BSDs, Windows.

It speaks the `TLS_CHACHA20_POLY1305_SHA256` cipher suite with the X25519
key-exchange group, which is accepted by essentially every modern TLS 1.3
server (OpenSSL, BoringSSL, nginx, and the large CDNs).

## What's implemented

* **Key exchange** — X25519 (RFC 7748), constant-time Montgomery ladder.
* **Record protection** — ChaCha20-Poly1305 AEAD (RFC 8439).
* **Key schedule** — HKDF-Extract/Expand + HKDF-Expand-Label / Derive-Secret
  (RFC 5869, RFC 8446 §7.1) over pure HMAC-SHA-256.
* **Handshake** — ClientHello (SNI, supported_versions, supported_groups,
  signature_algorithms, key_share), ServerHello parsing, the full
  handshake/application key schedule, decryption of the server flight
  (EncryptedExtensions, Certificate, CertificateVerify, Finished),
  verification of the server Finished MAC, and the client Finished.
* **Application data** — encrypted `tls_write` / `tls_read`, transparently
  consuming post-handshake messages (session tickets, key updates).

Each of the crypto primitives is validated against its RFC's published
known-answer vectors (`compiler/tests/x25519_vectors`,
`chacha20poly1305_vectors`, `hkdf_vectors`), and the end-to-end handshake
has been verified against both an OpenSSL `s_server` and Cloudflare's
production endpoint.

## ⚠ Security status — read this

This release establishes an **encrypted** channel but does **not yet
verify the server's certificate chain**. That means it protects against
passive eavesdropping but **not** against an active man-in-the-middle —
it is at the level of `sslmode=require`, not `verify-full`.

The handshake captures the server's leaf certificate
(`conn.server_cert`, DER) so that a certificate-verification layer
(ASN.1/X.509 parsing, RSA/ECDSA/Ed25519 signature checking, chain
building against the system trust store, and hostname matching) can be
added on top. Until that lands, do not rely on this for authenticating a
remote server over an untrusted network.

## API

```
( tls_connect host port server_name ) → !*TlsConn TlsErr
( tls_write conn ( Vec u ) bytes )     → !v TlsErr
( tls_read conn max )                  → !( Vec u ) TlsErr   // [] at EOF
( tls_close conn )                     → v
```

## Demo

`src/https_get.nu` is a minimal HTTPS client:

```
./nurl.sh packages/tls/src/https_get.nu https_get
./https_get cloudflare.com 443 /
```

It completes the TLS 1.3 handshake and prints the (decrypted) HTTP
response.
