# Cryptography & TLS

NURL ships its own cryptography and TLS stack written entirely in NURL, on top
of `libc` only — **no OpenSSL, no libcrypto, no libssl**. A default
`./build.sh` binary links `libc` only; the toolchain self-test
confirms `NEEDED = libc.so.6` for a program that uses the TLS client and
server. This document describes what is implemented, how it is built, the
side-channel posture, and the trust model — including what it deliberately
does **not** promise.

> **One-line summary.** The primitives are correct (KAT-verified, interops
> with OpenSSL/curl/browsers) and the protocol enforces the standard TLS 1.3
> authentication and downgrade controls. On the **timing/cache** side-channel
> axis the EC and symmetric primitives are constant-time including operand
> timing (by construction + code review, not yet statistically measured), and
> so is RSA, on its own fixed-width Montgomery field.
> **Power/EM (DPA/template) side-channels are out of scope for the whole
> software stack** — that needs hardware. Where a guarantee is narrower than
> OpenSSL's (revocation, name constraints, all power/EM), this document says
> so.

---

## 1. What's implemented

Sources live in `stdlib/std/` (with JWT and SSH protocol helpers in `stdlib/ext/`).

| Area | Module(s) | Notes |
|---|---|---|
| Hashes | `hash_sha256` (SHA-224/256), `hash_sha512` (SHA-384/512, SHA-512/224, SHA-512/256), `hash_sha3`, `hash_blake2b`, `hash_blake3`, `hash_sha1`, `hash_md5` | SHA-1/MD5 for legacy interop only (never trusted for signatures) |
| XOF | `hash_sha3` (SHAKE128/256) | extendable output, incremental squeeze; ML-KEM is built on it |
| Post-quantum KEM | `mlkem` (ML-KEM-512/768/1024, FIPS 203) | checked byte-for-byte against NIST's ACVP vectors |
| Post-quantum signature | `mldsa` (ML-DSA-44/65/87, FIPS 204) | pure, external-mu and HashML-DSA; all 615 ACVP cases |
| Post-quantum signature, hash-based | `slhdsa` (SLH-DSA, FIPS 205, SHAKE family) | six parameter sets; security rests only on the hash |
| HMAC / KDF | `hkdf`, `pbkdf2`, `scrypt` | HKDF-Expand-Label for TLS 1.3 |
| AEAD | `aes_gcm` (AES-128/256-GCM), `chacha20poly1305` | the two TLS 1.3 record ciphers |
| ECDH / signatures | `x25519`, `ed25519`, `ecdsa_p256` (P-256 + P-384), `p256_field`, `minisign` | X25519: RFC 7748 ladder and ref10's signed-digit fixed base over a four-word (radix 2^64) lazily reduced field; Ed25519 on the five-limb radix-2^51 field (curve25519-donna-c64); `p256_field` is the dedicated **constant-time** fixed-limb GF(p) for the P-256 secret path; `minisign` verifies Ed25519 + BLAKE2b release/package signatures |
| RSA | `rsa`, `rsa_mont` (PKCS#1 v1.5 verify, PSS verify + sign) | fixed-width Montgomery arithmetic; CRT signing with exponent blinding and a fault check |
| Bignum | `bigint` | sign-magnitude, schoolbook mul / long division, `modpow`, `modinv` |
| X.509 | `x509`, `tls_verify`, `x509_gen`, `csr`, `pkey` | DER parser + chain/host/policy verification; generates self-signed P-256 and ML-DSA certificates; PKCS#10 requests; PEM private-key loading (SEC1 / PKCS#8 P-256, RSA, ML-DSA). `tls_verify` anchors to the system bundle, or to `$SSL_CERT_FILE` when set — which **replaces** the bundle rather than adding to it, matching OpenSSL, and fails closed with "no trust anchor" if the path is unreadable |
| CSR | `csr` | PKCS#10 (RFC 2986) parser, generator (ECDSA P-256, Ed25519), self-signature verifier (ECDSA P-256, Ed25519, RSA, ML-DSA), and CA certificate issuance |
| JWT & SSH | `ext/jwt`, `ext/http_jwt`, `ssh`, `ext/ssh_ed25519` | HS256, EdDSA (Ed25519), ES256 (ECDSA P-256 + SHA-256, RFC 7518 §3.1), HTTP bearer-auth middleware, OpenSSH key/signature handling |
| TLS | `tls` (client, 1.3 + 1.2 fallback), `tls_server` (1.3) | record layer, key schedule, handshake; the client offers `X25519MLKEM768` first |
| Randomness | `random` (CSPRNG), `rng` (xoshiro256\*\*, **not** crypto) | |
| Constant-time | `subtle` | length-independent secret comparison |

`std/tls.nu` / `std/tls_server.nu` and `std/net.nu`'s `tcp_listen_tls` /
`tls_connect` are thin layers over these. `tls_connect` does **verify-full by
default** (chain + hostname + validity); the no-verification path is a
separate, explicitly-named `tls_connect_insecure`.

### Randomness

All key, nonce, salt and blinding-factor entropy comes from one runtime
bridge, `nurl_rand_fill`, which selects the OS CSPRNG per platform —
`getrandom(2)` on Linux, `arc4random_buf` on macOS, `BCryptGenRandom` on
Windows, `/dev/urandom` otherwise. Every draw — the crypto modules
(`std/tls.nu`, `std/rsa.nu`, `std/x509_gen.nu`) and `std/random.nu`'s
convenience draws (`rand_u64`, `rand_hex_str`) alike — checks its return
value and **fails closed** (panics) rather than proceed with predictable
bytes. `std/rng.nu`
(xoshiro256\*\*) is a separate, clearly-marked **non-cryptographic** PRNG
for simulations and is never used by this stack.

### Post-quantum key exchange

`std/mlkem.nu` implements ML-KEM (FIPS 203) at all three parameter sets.
`std/tls.nu`'s client offers **`X25519MLKEM768`** (group `0x11ec`) as its
first preference, ahead of X25519 and P-256, so an ordinary
`tls_connect` gets post-quantum key exchange wherever the peer supports
it — which today includes Cloudflare, Google and a growing share of the
web. `tls_group` reports the group that was actually negotiated and
`tls_is_post_quantum` answers the direct question; both are worth
checking rather than assuming, because a server without ML-KEM falls
back to X25519 silently and the handshake looks identical otherwise.

The hybrid secret fed to the key schedule is the concatenation
`ML-KEM shared secret ‖ X25519 shared secret`. HKDF-Extract over the
pair is at least as strong as either half, so the session survives
ML-KEM being broken *and* survives X25519 being broken — adopting it is
never a downgrade. The X25519 half keeps its own RFC 8446 §7.4.2
all-zero check: testing only the concatenation would let a low-order
peer point zero the classical half while the ML-KEM half stayed random.

Offering the group makes the ClientHello roughly 1.5 kB, so it no longer
fits in a single TCP segment. That matches what every browser sending
this group already does, but a network path that silently drops large
handshake packets will now fail where it previously worked.

Decapsulation never reports failure — ML-KEM's *implicit rejection*
returns an unpredictable-but-deterministic key instead of an error, so a
probing attacker learns nothing. A wrong ciphertext therefore surfaces
as a handshake that fails at Finished, which is the intended behaviour
rather than a missing error path.

---

## 2. Correctness & interop

Every primitive has a known-answer test (KAT) in `compiler/tests/`
(`aes_gcm_vectors`, `chacha20poly1305_vectors`, `hkdf_vectors`,
`ecdsa_p256_*`, `ed25519_vectors`, `x25519_vectors` — with all 518 Wycheproof
X25519 cases in `x25519_wycheproof` — `rsa_*`, `x509_*`) and
run on every build. Interoperability was additionally validated manually at
development time (not re-run in CI): verify-full `tls_connect` GETs against
public sites and the `badssl.com` negative suite; `tls_server` handshakes
(RSA-2048 and EC P-256 leaf certs) with `curl`, browsers and a Python `ssl`
client; RSASSA-PSS cross-verification with OpenSSL.

ECDSA signing derives its **nonce** with **RFC 6979** (HMAC-SHA-256) — fully
deterministic, so the nonce needs no RNG and can never be reused, and the
signature is reproducible (hence KAT-testable). This is independent of the
side-channel **blinding** in §3, which separately draws a fresh random value
per signature: the *nonce* is deterministic, the *blinding factor* is random.

---

## 3. Side-channel posture

This is where a pure-software stack differs most from a hardware-accelerated
one.

**Threat model — in scope:** a remote or co-resident attacker observing
**timing and cache access patterns** across one or many operations (the
realistic threat for a network-facing TLS server). The hardening has two
layers: every secret-driven **control flow / memory-access pattern is uniform**
(no branch or table index on secret data — this defeats the cache / SPA
*sequence* attack), and on top of that the asymmetric private-key operations
are **blinded** so any residual operand-value-dependent timing carries no
signal.

**Threat model — OUT of scope for the entire software stack:** physical
**power / electromagnetic (DPA, SPA-power, template) side-channels.** Software
constant-time code is *not* a defense against these: the power a gate draws
still depends on the bits flowing through it, so a table-free or bitsliced AES
S-box and the P-256 field arithmetic both remain readable to an attacker with
a probe, branchless or not. Defending power/EM requires masking / hiding and ultimately
hardware countermeasures, which are not in this (or any pure-software) library.
Everything below concerns the **timing/cache** axis only.

**Caveat on the word "constant-time":** the constant-time properties claimed
here are **by construction and code review** — no secret-dependent branch, no
secret-indexed table, and (where stated) a fixed-width representation so
operand timing is value-independent. They have **not** yet been measured
statistically (e.g. dudect / ctgrind / ctverif). The cross-checks cited below
prove *correctness* (the code computes the right answer), which is a separate
axis from constant-timeness; an empirical leakage measurement is a tracked
follow-up. Hardening (timing/cache axis):

| Primitive | Countermeasure |
|---|---|
| AES S-box | **Constant-time, bitsliced**: the state is transposed so each 64-bit word holds one bit position of 64 bytes, and `SubBytes` is Boyar–Peralta's 113-gate boolean circuit evaluated on those words (the `aes_ct64` construction). Every operation is a word-wide AND/XOR — no table lookup, no branch, and nothing indexed by secret data. ShiftRows and MixColumns are shifts and XORs on the same words. The key schedule (once per key, not per block) instead uses the older per-byte form: `SubBytes(x) = Affine(x⁻¹ in GF(2⁸))` via a branchless GF multiply and a fixed-exponent (x²⁵⁴) inversion, verified equal to the reference S-box on all 256 inputs. |
| GHASH | **Constant-time on any CPU with a constant-time multiplier.** The GF(2¹²⁸) multiply is carry-less multiplication built from ordinary 64-bit integer multiplies (`ghash_ctmul64`): each operand is split into four interleaved bit groups so no carry crosses a kept bit, and the halves recombine by Karatsuba. No branch and no table, so nothing leaks the authentication key H through cache or control flow — but the timing rests on `imul` being data-independent, which holds on every mainstream 64-bit core and does *not* hold on some small in-order ARM cores (Cortex-M3/M0, early Cortex-A), where an early-terminating multiplier would reintroduce an operand-timing signal. |
| GCM / Poly1305 / TLS Finished tag compares | Constant-time (OR-accumulated XOR, no early exit). |
| RSA private key (PSS sign) | **Constant-time on the timing/cache axis** (`std/rsa_mont`): residues are n fixed 64-bit limbs, never normalised; the Montgomery multiply (FIPS on `nurl_mac`; on an ADX CPU, rows of `nurl_mac_row` with two carry chains; on AVX-512 IFMA, both CRT halves of an RSA-2048 signature at once in radix 2^52, [`adr/0002-ifma-rsa.md`](adr/0002-ifma-rsa.md)) and the final conditional subtraction are branch-free; the exponentiation is a fixed 4-bit window over a fixed number of windows whose table entry is chosen by a masked scan of all sixteen — no secret-dependent branch, address or operand duration. The key is prepared once (`RsaKey`: the factors' Montgomery contexts and the exponents as limbs, built at load and never written after, so every TLS worker signs with the same one) and when it carries its factors (every PKCS#1 / PKCS#8 key) the operation is CRT — two half-width exponentiations recombined by Garner — with **exponent blinding** (`d_p + r·(p − 1)` for a fresh 64-bit `r` per signature, so the exponent bits differ every time) and a **fault check**: the signature is verified mod p and mod q before it is released, so a computation fault in one half cannot leak a factor (Bellcore). Verification uses the same field with the public exponent (variable time, public data). Pinned by `tools/tests/test_rsa_sign.py`: CRT and plain-exponent PSS signatures byte-identical, and OpenSSL-verified, for 1024–4096-bit PKCS#1 and PKCS#8 keys. |
| P-256 secret scalar mult (ECDSA nonce / ECDHE) | **Constant-time on the timing/cache axis** (`std/p256_field`): a dedicated fixed-**4-limb (radix 2^64)** GF(p) field — Montgomery (CIOS) multiply, conditional-`±p` add/sub built on `nurl_addc`/`nurl_subb` carry chains, fixed-exponent Fermat inverse — never normalized, so even the *operand timing* is value-independent. **Two point paths, and the difference is the point.** *Variable-base* (ECDH against a peer's point) runs on Jacobian coordinates too: an affine table 1·Q … 15·Q built with one batch inversion, then 64 windows of four 3M+5S doublings and one 8M+3S mixed addition, a fixed number of steps regardless of the scalar's value, the secret digit never indexing the table — all sixteen entries are read every window and merged under an arithmetic equality mask. The scalar is reduced mod n first (constant time), and that makes the mixed addition **complete for every scalar**: before each addition the accumulator is m·Q with m = 0 (∞, committed by mask) or 16 ≤ m < n, and the entry is d·Q with 1 ≤ d ≤ 15, so the degenerate `acc = entry` case cannot occur — where without the reduction k = n + 30 would reach it. *Fixed-base* (`k·G`: the ECDSA nonce and ECDH keygen, where the point is the public generator) is **complete for every scalar** as well, by a different argument. The scalar is reduced mod n and Booth-recoded into 52 signed 5-bit digits d_w ∈ [−16, 16]; window w has its own affine table 1·32^w·G … 16·32^w·G (832 entries built once per process from G alone), so `k·G` is 52 mixed additions of a constant-time-selected, constant-time-negated entry and no doublings. The masks close `acc = ∞`, a zero digit and `acc = −entry` as in the variable-base path, and `acc = entry` cannot occur: before window w the accumulator is L·G with L = Σ_{v<w} d_v·32^v, and L − d_w·32^w is a non-zero signed-digit integer (its lowest non-zero digit is at most 16 in magnitude) smaller than n for w ≤ 50; for the top window of a reduced k the digit is 0, 1 or 2 and the only coincidences mod n would be k = 2^256 − n or 2^257 − 2n, where that digit is 0. (The 8-tooth comb this replaced skipped the reduction and accepted a ~2^-224 chance of the doubling case per addition.) No branch, no secret-dependent address, no operand-time dependence — **no blinding needed**. Verified for *correctness* (a separate axis from constant-timeness — see the caveat above): `compiler/tests/p256_ct_field.nu` pins the field against the bigint reference (400 field trials, 60 random variable-base scalar multiplies, and 24 edge scalars against two base points — including k = n + 30, k = n and k = 2²⁵⁶ − 1), `compiler/tests/p256_scalarmult_base_kat.nu` pins the comb against an independent Python implementation with 30 vectors chosen to exercise **every masked exceptional path** (k = 1/2/3, long runs of zero digits, all-negative and top-digit-2 Booth patterns, n − 1, scalars ≥ n, and the 2^256 − n and 2^257 − 2n of the completeness argument), and `compiler/tests/p256_comb_agree.nu` holds it to the variable-base ladder over 500 random scalars of 1 to 40 bytes. |
| P-256/P-384 verify | The scalars are **public** (verification), so this path needs no timing countermeasure at all — it needs speed, because a TLS client pays one verify per certificate in the chain and a JWT server one per request. Both curves compute u1·G + u2·Q as one Straus double-scalar pass on their fixed-limb Montgomery fields. P-256 shares the 256 doublings between the two scalars and adds 4-bit digits from two affine tables — G's, built once per process, and Q's, built per verify with one batch inversion; parsing, range checks and the on-curve test of Q run on the same fixed-width field, with no BigInt. P-384 runs `std/p384_field`'s looped 6-limb CIOS engine over the RCB complete formula. Exactness in every case is load-bearing for *correctness*, not timing: an adversarially crafted (r, s, Q) can steer the accumulator and the entry into any relation — equal, negated, either at infinity — and the classic Jacobian add degenerates exactly there. P-256's mixed addition handles those by branching (`_p256_jmadd_vt`: equal doubles, negated becomes ∞), which public data allows. Digests longer than the group order are truncated to their leftmost qlen bits (FIPS 186-5 §6.4.1), pinned against OpenSSL across both curves and five digest widths in `compiler/tests/ecdsa_verify_matrix.nu`. |
| X25519 | Montgomery ladder (RFC 7748) with one branchless conditional swap per bit; fixed iteration count. The public key is ref10's fixed-base method on the Edwards form: 64 signed radix-16 digits recoded without a branch, each table row scanned whole under a mask and its sign applied by mask, a fixed step sequence. The field underneath is four 64-bit words held as `u64` locals, lazily reduced (any value < 2^256): each product one `nurl_mac`, the carry out of bit 256 folded back as ×38 by a fixed instruction sequence — no branch on data anywhere in it. |
| Ed25519 | Deterministic nonce (RFC 8032), so no per-signature secret randomness to leak. The scalar multiply is a **fixed 4-bit window** over the complete twisted-Edwards addition: four doublings and one addition per nibble, a fixed `2·len(scalar bytes)` windows regardless of the scalar. The window digit is secret, so the table is never indexed by it — all sixteen entries are read every window and merged under an arithmetic equality mask (a full 64-bit one, since the field's radix-2^51 limbs run up to ~2^54 and a 32-bit mask would clip them), and digit 0 reads the identity, which the complete formula absorbs. |
| Secret comparison | `std/subtle.nu` — duration depends only on input *length*, never contents. |

### State by primitive (timing/cache axis; power/EM is out of scope for all — see above)

- **P-256 (ECDSA signing, ECDHE), X25519, Ed25519, AES-GCM, ChaCha20-Poly1305,
  GHASH, all tag compares** — constant-time *including operand timing*: no
  secret-dependent branch, no secret-indexed table, and a fixed-width field
  representation (P-256 via `std/p256_field`; X25519 via four fixed 64-bit
  words, Ed25519 via five limbs at radix 2^51) so even `mul`/`reduce` duration
  is value-independent. This resists a *single-trace* **timing/cache**
  observer (not just the multi-trace remote attacker) — but, like all
  software constant-time code, it does **not** resist a power/EM
  (DPA/template) attacker, which is out of scope stack-wide.

- **RSA private-key exponentiation** — constant-time *including operand
  timing* as well, on its own fixed-width field (`std/rsa_mont`): fixed limbs,
  a fixed window, masked table reads, branch-free reductions. On the CRT path
  each signature's exponents are blinded (`d_p + r·(p − 1)`) and the result is
  checked mod p and mod q before release. The plain-exponent path (a caller
  that passes only d) is constant-time too, without the blinding. Power/EM
  remains out of scope for RSA too — and for everything.

### Practical guidance

- **AES-GCM where the CPU has AES instructions, ChaCha20-Poly1305
  elsewhere** — which is what TLS negotiates. Both are constant-time. On a
  CPU with the hardware crypto tier (docs/spec.md §4.1b) AES-GCM runs on
  AES-NI and PCLMULQDQ (~3 GB/s on a Haswell) — or AES and PMULL on
  AArch64 (Apple Silicon, Graviton) — and on VAES / VPCLMULQDQ
  where those exist (ymm, or zmm under AVX-512: ~8–11 GB/s on a Sapphire
  Rapids, measured on 16 KB records with a prepared key), against
  ChaCha20-Poly1305's ~1.1–1.4 GB/s. Without the tier AES-GCM falls back
  to a bitsliced cipher that is constant-time without AES instructions
  but ~113 MB/s — then ChaCha20-Poly1305 is the cipher to use.

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
3. **Side-channel hardened on the timing/cache axis.** The EC path (P-256
   ECDSA/ECDHE, X25519, Ed25519) and all symmetric primitives are constant-time
   *including operand timing* — no secret-dependent branch, table index, or
   value-dependent duration — so they resist a single-trace **timing/cache**
   observer. RSA's private exponentiation is constant-time on the same terms,
   on its own fixed-width field, with per-signature exponent blinding on the
   CRT path. These properties are by-construction and code-reviewed, not yet
   measured statistically (dudect/ctgrind — a tracked follow-up).
4. **Power / EM (DPA, SPA-power, template) side-channels are OUT of scope for
   the entire software stack.** Software constant-time code does not defend
   them — a table-free or bitsliced AES S-box still leaks through power draw,
   and so does the P-256 field. Defending power/EM needs
   masking/hiding and ultimately hardware; use a hardware-backed / audited
   library (HSM, secure element, AES-NI + a vetted bignum) where that threat
   model applies.

An external audit and statistical timing measurement (dudect-style) remain
open work — see [`ROADMAP.md`](../ROADMAP.md).

---

## 7. Building

Nothing special: a default `./build.sh` produces binaries that link `libc`
only. `libssl`/`libcrypto` are absent from the source tree entirely. See
[`docs/BUILDING.md`](BUILDING.md) for the bootstrap and
[`docs/NETWORKING.md`](NETWORKING.md) for the socket layer the TLS stack sits
on.
