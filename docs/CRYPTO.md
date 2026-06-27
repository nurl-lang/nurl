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
> authentication and downgrade controls. The side-channel hardening targets
> the **remote / co-resident timing** attacker (the network threat model);
> it is not a defense against an attacker with local power/EM probes. Where a
> guarantee is narrower than OpenSSL's, this document says so.

---

## 1. What's implemented

All sources live in `stdlib/std/`.

| Area | Module(s) | Notes |
|---|---|---|
| Hashes | `hash_sha256`, `hash_sha512`, `hash_sha1`, `hash_md5`, `hash_blake3` | SHA-1/MD5 for legacy interop only (never trusted for signatures) |
| HMAC / KDF | `hkdf`, `pbkdf2`, `scrypt` | HKDF-Expand-Label for TLS 1.3 |
| AEAD | `aes_gcm` (AES-128/256-GCM), `chacha20poly1305` | the two TLS 1.3 record ciphers |
| ECDH / signatures | `x25519`, `ed25519`, `ecdsa_p256` (P-256 + P-384) | TweetNaCl-derived 25519; Jacobian P-256/384 |
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
| P-256 scalar mult (`__jmul`) | **Constant control flow**: a branchless Coron always-add ladder — every bit does a double and an add, then a constant-time point select keeps the add iff the bit was set. No secret-bit branch; per-bit operation sequence is uniform. |
| ECDSA nonce / ECDH scalar | **Scalar blinding** on top (walk `k + r·n` instead of `k`; `n·P = O`) **+ projective coordinate randomization** (`(X,Y,Z) → (λ²X, λ³Y, λZ)`). Coron CHES'99 #1 and #3; randomizes the intermediate values per call, covering the residual operand timing. |
| X25519 | Montgomery ladder with a branchless constant-time conditional swap (TweetNaCl); fixed iteration count. |
| Ed25519 | Deterministic nonce (RFC 8032), so no per-signature secret randomness to leak. |
| Secret comparison | `std/subtle.nu` — duration depends only on input *length*, never contents. |

### Honest limitation: variable-time bignum (operand timing only)

The control-flow / access-pattern leak is closed: RSA modexp and P-256 scalar
multiply now have a uniform, secret-independent operation sequence (no
secret-dependent branch, no secret-indexed table). What remains is one finer
layer — `std/bigint.nu` is a generic sign-magnitude bignum that **normalizes
(trims leading-zero limbs)**, so its `mul`/`rem` run in time proportional to
operand *magnitude*. So the field/scalar arithmetic is not yet *operand-time*
constant. This residual is **covered by the per-operation blinding** (every
trace runs on randomized operands, carrying no signal an attacker can
aggregate), which is exactly the OpenSSL posture for the same arithmetic.

Eliminating even that residual — to resist a *single-trace* local power/EM
attacker — requires a dedicated **fixed-limb-count field** with constant-time
multiply and reduction (no normalization). That is a deliberate follow-up
tracked in `TODO.md` §10, not a property this software stack claims today. The
boundary drawn here (uniform control flow + blinded operands; not fixed-limb
constant-time arithmetic) is the standard one for a pure-software TLS stack
against the network / co-resident threat model.

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
3. **Hardened against the remote/co-resident timing attacker** — constant-time
   symmetric primitives and tag compares; uniform secret-independent control
   flow in RSA modexp and P-256 scalar multiply; blinded asymmetric private-key
   operations on top.
4. **Not** hardened against a local single-trace power/EM attacker — the bignum
   layer's mul/rem are still operand-time-dependent (covered by blinding, not
   eliminated). Use a hardware/audited library where that threat model applies.

The full audit and the residual follow-ups (notably a constant-time fixed-limb
P-256 field) are tracked in `TODO.md` §9–§10.

---

## 7. Building

Nothing special: a default `./build.sh` produces binaries that link `libc`
only. `libssl`/`libcrypto` are absent from the source tree entirely. See
[`docs/BUILDING.md`](BUILDING.md) for the bootstrap and
[`docs/NETWORKING.md`](NETWORKING.md) for the socket layer the TLS stack sits
on.
