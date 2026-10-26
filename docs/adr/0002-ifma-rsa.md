# ADR 0002 — RSA on AVX-512 IFMA: both CRT halves at once, radix 2^52

Status: accepted (2026-10-26, agora #105)

## Context

After ADR 0001 (the ADX rows), an RSA-2048 signature took ~0.62 ms on an
i7-11850H against 0.25 ms for aws-lc on the same CPU. A profile of
aws-lc showed it does not sign with mulx/adx at all here: its time is in
`rsaz_amm52x20_x2_ifma256`, an AVX-512 IFMA Montgomery multiply.

IFMA's VPMADD52LUQ / VPMADD52HUQ add the low or high 52 bits of the
product of two 52-bit numbers to a 64-bit lane. A number held as 52-bit
limbs in 64-bit lanes thus takes four limb products per ymm instruction,
and every carry stays in its lane's top 12 bits until one normalising
pass — no carry chain at all, where the scalar forms (FIPS, ADX rows)
serialise every product on one or two flags.

A C prototype measured first (clang 18, `-march=icelake-server`), for
the 1024-bit multiply of an RSA-2048 CRT half:

| Form | Time per multiply |
|---|---|
| ADX rows (ADR 0001) | 203–211 ns |
| IFMA, one multiply | ~150 ns |
| IFMA, two independent multiplies interleaved | ~88 ns |

One multiply alone is latency-bound: the next limb's reduction digit
(a scalar multiply of lane 0) waits for the vector work. Two independent
multiplies — the p half and the q half of the CRT — hide each other's
scalar step.

## Decision

1. **A tier, not a gate around one kernel.** `nurl_v256_madd52lo` /
   `_madd52hi (acc, a, b)` are crypto-tier primitives under the AES
   tiers' contract: x86-64-v4 + AVX512_IFMA (on ymm, so AVX-512VL and no
   512-bit vectors), the runtime's CPUID answer `nurl_cpu_x86_ifma`
   (leaf 7 EBX bit 21 plus the v4 bits and XCR0), `NURL_CPU_IFMA=0`, an
   entry gate, stubs off x86. Like SHA it is its own bit (16) of the tier
   set, on no chain with AES: Cannon Lake has IFMA without VAES. The
   one portable operation the multiply also needs, moving an
   accumulator one limb down across registers, is a generic
   `nurl_v256_shrlane64` (a shufflevector: VALIGNQ on AVX-512VL, a
   permute and blend on AVX2).
2. **The kernel is NURL, not asm.** Unlike ADR 0001 nothing here needs
   instructions LLVM will not select: the intrinsics are the
   instructions. `std/rsa_mont.nu` writes the almost Montgomery
   multiply (AMM: a·b·R'^-1 mod m below 2m for a, b < 2m and 4m <
   R' = 2^1040) for two moduli at once, and the exponentiation around
   it, with the fixed 4-bit window and masked table scan of
   `_rm_pow_ct`.
3. **The whole exponentiation is one tier body.** The `simd @` entry
   (`__rm_pow2_52`) calls inline helpers that call inline helpers using
   the primitives. nurlc counted only a callee that used a primitive
   itself, so the first build gave the entry baseline clones calling
   each helper's gated original out of line, every v256 crossing by
   pointer: 4.1 ms a signature. The fix is in the compiler — an inline
   function is not a call, so the tier it reaches counts as the body's
   own (flush_simd_deferred) — and `crypto_tier_ir.sh` checks the entry
   is one gated IFMA definition with its helpers inlined.
4. **The 52-bit domain from entry to exit.** The moduli's 52-bit forms
   and R'^2 mod m are derived once per key (in `RsaMont`, for 16-limb
   moduli). A signature converts the two plain bases in, exponentiates,
   leaves the domain by AMM(x, 1) and reduces once — Garner and the
   fault check stay as they were. `_rm_pow2_ct` is the boundary: two
   secret-exponent powers, plain in and out, at once on the IFMA tier
   with two 1024-bit moduli and one after the other by `_rm_pow_ct`
   otherwise.
5. **One width.** 20 limbs (five registers per operand, ten
   accumulators for the pair) is RSA-2048's CRT, the TLS case. RSA-3072
   and -4096 (30 and 40 limbs) are the same shape with more registers,
   and stay on the ADX rows until measured.

## Consequences

Measurements are on an i7-11850H.

| RSA-2048 PSS signature | Time |
|---|---|
| ADX rows (before; `NURL_CPU_IFMA=0`) | 0.65 ms |
| IFMA, both halves at once | 0.24–0.31 ms (median ~0.27) |
| aws-lc (`tls_prims`) | 0.22–0.24 ms |

- **Correctness:** `rsa_pow2_agree` holds `_rm_pow2_ct` to
  `bigint_modpow` for pairs of 1024-bit moduli (different, equal) and a
  1024/960-bit pair, with bases 0, 1, m − 1 and random, on both tiers;
  `rsa_pss_sign` and `tools/tests/test_rsa_sign.py` (OpenSSL verifies)
  run end to end on both.
- **A bigint bug on the way:** `bigint_modpow` ran its ladder for
  bit-length(m) steps, so an exponent wider than the modulus — the
  blinded CRT exponent — lost its top bits. It now covers the modulus's
  whole limbs, or the exponent's if it has more.
- **Constant time:** no branch or memory index in the AMM, the table
  scan or the conversions depends on a secret; the exponent's windows
  are read at public positions.
