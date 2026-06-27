# Cryptography & TLS

NURL ships its own cryptography and TLS stack written entirely in NURL, on top
of `libc` only — **no OpenSSL, no libcrypto, no libssl**. A default
`./build.sh` binary links `libc` (plus `libm`); the toolchain self-test
confirms `NEEDED = libc.so.6` for a program that uses the TLS client and
server. This document describes what is implemented, how it is built, the
side-channel posture, and the trust model — including what it deliberately
does **not** promise.

> **One-line summary.** The primitives are correct (KAT-verified, interops
> with OpenSSL/curl/browsers) and the protocol enforces the standard TLS 1.3
> authentication and downgrade controls. The EC and symmetric primitives are
> **fully constant-time** (including operand timing); the only side-channel
> residual is RSA's `bigint` operand timing, covered by base blinding against
> the remote/co-resident attacker. Where a guarantee is narrower than
> OpenSSL's (revocation, name constraints, single-trace RSA), this document
> says so.

---

## 1. What's implemented

All sources live in `stdlib/std/`.

| Area | Module(s) | Notes |
|---|---|---|
| Hashes | `hash_sha256`, `hash_sha512`, `hash_sha1`, `hash_md5`, `hash_blake3` | SHA-1/MD5 for legacy interop only (never trusted for signatures) |
| HMAC / KDF | `hkdf`, `pbkdf2`, `scrypt` | HKDF-Expand-Label for TLS 1.3 |
| AEAD | `aes_gcm` (AES-128/256-GCM), `chacha20poly1305` | the two TLS 1.3 record ciphers |
| ECDH / signatures | `x25519`, `ed25519`, `ecdsa_p256` (P-256 + P-384), `p256_field` | TweetNaCl-derived 25519; `p256_field` is the dedicated **constant-time** fixed-limb GF(p) for the P-256 secret path |
| RSA | `rsa` (PKCS#1 v1.5 verify, PSS verify + sign) | built on `bigint` |
| Bignum | `bigint` | sign-magnitude, schoolbook mul / long division, `modpow`, `modinv` |
| X.509 | `x509`, `tls_verify` | DER parser + chain/host/policy verification |
| TLS | `tls` (client, 1.3 + 1.2 fallback), `tls_server` (1.3) | record layer, key schedule, handshake |
| Randomness | `random` (CSPRNG), `rng` (xoshiro256\*\*, **not** crypto) | |
| Constant-time | `subtle` | length-independent secret comparison |

The TLS package (`packages/tls`) and `std/net.nu`'s `tcp_listen_tls` /
`tls_connect` are thin layers over these. `tls_connect` does **verify-full by
default** (chain + hostname + validity); the no-verification path is a
separate, explicitly-named `tls_connect_insecure`.

### Randomness

`std/random.nu` is the only entropy source for keys, nonces, salts and
blinding factors. It is a single runtime bridge, `nurl_rand_fill`, that selects
the OS CSPRNG per platform — `getrandom(2)` on Linux, `arc4random_buf` on
macOS/BSD, `BCryptGenRandom` on Windows, `/dev/urandom` otherwise. Every
draw checks the return value and **fails closed** (panics) rather than
proceeding with predictable bytes. `std/rng.nu` (xoshiro256\*\*) is a separate,
clearly-marked **non-cryptographic** PRNG for simulations and is never used by
this stack.

---

## 2. Correctness & interop

Every primitive has a known-answer test (KAT) in `compiler/tests/`
(`aes_gcm_vectors`, `chacha20poly1305_vectors`, `hkdf_vectors`,
`ecdsa_p256_*`, `ed25519_vectors`, `x25519_vectors`, `rsa_*`, `x509_*`), run
on every build, and the stack is exercised against real peers:

- `tls_connect` performs verify-full GETs against `example.com`, Google,
  Cloudflare and `*.badssl.com`; self-signed / wrong-host / expired /
  untrusted-root certificates are rejected.
- `tls_server` (RSA-2048 and EC P-256 leaf certs) completes handshakes with
  `curl`, browsers and a Python `ssl` client.
- RSASSA-PSS signatures produced here verify under OpenSSL and vice-versa.

ECDSA signing derives its **nonce** with **RFC 6979** (HMAC-SHA-256) — fully
deterministic, so the nonce needs no RNG and can never be reused, and the
signature is reproducible (hence KAT-testable). This is independent of the
side-channel **blinding** in §3, which separately draws a fresh random value
per signature: the *nonce* is deterministic, the *blinding factor* is random.

---

## 3. Side-channel posture

This is where a pure-software stack differs most from a hardware-accelerated
one, and where the 2026-06 security sweep (§9–§10 of `TODO.md`) focused. The
**threat model is a remote or co-resident attacker observing timing and cache
access patterns across many operations** — the realistic threat for a
network-facing TLS server. The hardening has two layers: every secret-driven
**control flow / memory-access pattern is uniform** (no branch or table index
on secret data — this is what defeats the cache / SPA *sequence* attack), and
on top of that the asymmetric private-key operations are **blinded** so the
residual operand-value-dependent timing carries no signal. Hardening:

| Primitive | Countermeasure |
|---|---|
| AES S-box | **Constant-time**: `SubBytes(x) = Affine(x⁻¹ in GF(2⁸))` computed with a branchless GF multiply and a fixed-exponent (x²⁵⁴) inversion — no table lookup or branch indexed by secret data. Verified equal to the reference S-box on all 256 inputs. `xtime` (MixColumns) is likewise branchless. |
| GHASH | Branchless: the GF(2¹²⁸) multiply uses mask arithmetic, so its timing does not leak the authentication key H. |
| GCM / Poly1305 / TLS Finished tag compares | Constant-time (OR-accumulated XOR, no early exit). |
| RSA modexp (`bigint_modpow`) | **Constant control flow**: a Montgomery powering ladder — exactly two modular multiplies per bit for a fixed count = bit-length(`m`), register choice by a constant-time conditional swap. The square-multiply trace is uniform regardless of the secret exponent `d` (no naive "multiply only on 1-bits" leak). No CRT is used (single direct modexp with the full `d`), so there is no CRT-reduction timing surface (Brumley–Boneh class). |
| RSA private key (PSS sign) | **Base blinding** on top: `s = ((EM·rᵉ)ᵈ · r⁻¹) mod n` for a fresh random `r` per signature. `rᵉᵈ ≡ r (mod n)`, so the result is identical, but the value fed to the (still operand-time-dependent) `bigint` mul/rem is randomized — covering the residual timing the ladder's uniform control flow does not. |
| P-256 secret scalar mult (ECDSA nonce / ECDHE) | **Fully constant-time** (`std/p256_field`): a dedicated fixed-16-limb GF(p) field — Montgomery (CIOS) multiply, conditional-`±p` add/sub, fixed-exponent Fermat inverse — never normalized, so even the *operand timing* is value-independent. Points use the Renes–Costello–Batina **complete** addition formula (a = −3), correct for all inputs incl. identity, in a branchless always-add ladder with constant-time point select. No branch, no table index, no operand-time dependence, **no blinding needed**. Verified: the field matches the bigint reference (2000 random cases) and the scalar multiply matches both the bigint path and Python `cryptography`. |
| P-256/P-384 verify (`__jmul`) | Branchless ladder over the bigint field, but the scalars are **public** (verification), so the bigint operand timing is harmless here. |
| X25519 | Montgomery ladder with a branchless constant-time conditional swap (TweetNaCl); fixed iteration count. |
| Ed25519 | Deterministic nonce (RFC 8032), so no per-signature secret randomness to leak. |
| Secret comparison | `std/subtle.nu` — duration depends only on input *length*, never contents. |

### State by primitive

- **P-256 (ECDSA signing, ECDHE), X25519, Ed25519, AES-GCM, ChaCha20-Poly1305,
  GHASH, all tag compares** — fully constant-time, *including operand timing*:
  no secret-dependent branch, no secret-indexed table, and a fixed-width field
  representation (P-256 via `std/p256_field`; 25519 via the TweetNaCl packed
  limbs) so even `mul`/`reduce` duration is value-independent. This resists not
  only the remote/co-resident attacker but a *single-trace* observer of these
  operations.

- **RSA private-key exponentiation** — uniform control flow (the Montgomery
  powering ladder) but the underlying `std/bigint` `mul`/`rem` still **normalize
  (trim leading-zero limbs)**, so their duration tracks operand *magnitude*.
  That residual is **covered by base blinding** (every signature runs on a fresh
  randomized operand, so no signal aggregates across traces) — exactly OpenSSL's
  posture for the same arithmetic. A *single-trace* local power/EM attacker is
  out of scope for RSA until a dedicated fixed-limb RSA modular multiply lands
  (tracked in `TODO.md` §10). RSA is the legacy path; the EC path above is the
  primary one for modern internet-facing TLS and carries no such residual.

### Practical guidance

- **Prefer ChaCha20-Poly1305.** It is naturally constant-time and fast; it is
  the default record cipher. The constant-time AES is correct but slower than
  a table implementation (it computes the S-box per byte), and exists for peers
  that only offer AES-GCM.

---

## 4. TLS protocol controls

`tls.nu` (client) and `tls_server.nu` implement TLS 1.3 (RFC 8446) with a
TLS 1.2-ECDHE-AEAD fallback on the client. The protocol-level controls:

- **Verify-full by default.** `tls_connect` checks the CertificateVerify
  signature against the leaf key, the full certificate chain, the hostname,
  and the validity window, and closes the connection (`TlsBadCert`) on any
  failure. The non-verifying path is a separately-named opt-in.
- **Key schedule.** HKDF-Expand-Label / Derive-Secret per RFC 8446, with
  handshake and application traffic secrets correctly separated and transcript
  hashes taken at the right message boundaries. The Finished MAC is verified in
  constant time before application keys are derived.
- **Contributory ECDHE.** Both client and server reject an all-zero X25519 /
  P-256 ECDHE shared secret (RFC 8446 §7.4.2), and the P-256 path validates the
  peer's key share is a valid on-curve point before use (invalid-curve guard).
- **Downgrade protection.** A 1.3-capable client that negotiates 1.2 checks the
  RFC 8446 §4.1.3 server-random downgrade sentinel and aborts. Only AEAD suites
  are offered/accepted on the 1.2 path (no CBC / RC4 / export), so there is no
  Lucky13-style padding-oracle surface.
- **Record nonces.** Per-record nonce = static IV XOR the 64-bit sequence
  number; the sequence resets on every key epoch, so a nonce is never reused
  within a key.
- **No 0-RTT / early data**, so no replay surface.

---

## 5. Certificate / PKI verification

`x509.nu` is a focused DER parser; `tls_verify.nu` is the chain-validation
policy. Trust anchors come from the system bundle
(`/etc/ssl/certs/ca-certificates.crt`, then `/etc/pki/tls/certs/ca-bundle.crt`,
then `/etc/ssl/cert.pem`). Enforced:

- **Chain signatures** — each certificate is verified against the next cert's
  key, up to a trusted root.
- **Basic Constraints** — every signing (issuer) certificate must assert
  `cA:TRUE`; `pathLenConstraint` is honoured. This closes the classic
  "any leaf can sign for any host" break.
- **Key usage / EKU** — a CA must assert `keyCertSign` (when it carries a
  keyUsage); a leaf carrying an EKU must assert `serverAuth` (or `anyEKU`).
- **Hostname** — matched against `subjectAltName` dNSName only (never CN), with
  single-leftmost-label wildcards only (`*.example.com`, not `*.com` or
  `*foo.com`), and embedded-NUL dNSNames rejected. IP-literal hosts match
  `iPAddress` SANs only.
- **Validity** — `notBefore`/`notAfter` checked against the system clock on the
  leaf, every issuer, and the anchor.
- **Algorithm strength / confusion** — MD5 and SHA-1 signatures are refused;
  the signature algorithm must match the issuer key type (no RSA-key/ECDSA-sig
  confusion); RSA keys below 2048 bits are rejected; PKCS#1 v1.5 verification
  is strict (no e=3 / BERserk trailing-garbage forgery); the presented chain is
  length-capped.

**Not enforced (narrower than OpenSSL — name these explicitly):**

- **Revocation is not checked.** There is no OCSP (stapled or live) and no CRL
  fetch, so a certificate that is **revoked but otherwise valid and unexpired
  is accepted**. If you need revocation, terminate TLS behind a proxy that
  checks it, or keep the trust store tight and rotate.
- **Name constraints** (RFC 5280 §4.2.1.10) are not parsed or enforced, so a
  technically-constrained sub-CA could issue outside its permitted name space
  undetected. Most software stacks also skip this; noted for completeness.

---

## 6. Soundness contract

Like the borrow checker (see [`docs/MEMORY.md`](MEMORY.md)), this stack aims to
be **sound, not a hardware-grade side-channel-free implementation**:

1. **Correct** — KAT-verified, interops with OpenSSL/browsers/curl.
2. **Authenticated** — TLS 1.3 controls and X.509 policy are enforced by
   default; the only way to skip them is the explicitly-named insecure path.
   **Revocation (OCSP/CRL) and X.509 name constraints are not checked** — see
   §5 "Not enforced".
3. **Side-channel hardened.** The EC path (P-256 ECDSA/ECDHE, X25519, Ed25519)
   and all symmetric primitives are fully constant-time *including operand
   timing* — no secret-dependent branch, table index, or value-dependent
   duration — so they resist even a single-trace local observer. RSA's private
   exponentiation has uniform control flow plus base blinding, which defeats the
   remote/co-resident attacker; its `bigint` operand timing is the one residual.
4. **One documented residual:** RSA modular multiply is still operand-time-
   dependent under the blinding (single-trace local power/EM on *RSA only* is
   out of scope until a fixed-limb RSA multiply lands). Use a hardware/audited
   library if that exact threat model applies to your RSA keys.

The full audit and the remaining RSA fixed-limb follow-up are tracked in
`TODO.md` §9–§10.

---

## 7. Building

Nothing special: a default `./build.sh` produces binaries that link `libc`
only. `libssl`/`libcrypto` are absent from the source tree entirely. See
[`docs/BUILDING.md`](BUILDING.md) for the bootstrap and
[`docs/NETWORKING.md`](NETWORKING.md) for the socket layer the TLS stack sits
on.
