# ADR 0001 — Two carry chains: `nurl_mac_row` on the ADX tier

Status: accepted (2026-10-25, agora #95)

## Context

Every big-number kernel in the stdlib is a chain of multiply-accumulates
with carries: RSA's Montgomery arithmetic (`std/rsa_mont.nu`), the P-256
and P-384 fields, X25519. `nurl_mac_lo/_hi` lowers one limb product to
`mul` + `add` + `adc`. Every carry goes through x86's one carry flag, so
a row of products is one serial chain.

Since Broadwell (Intel) and Zen (AMD), x86 has:

- MULX (BMI2), a widening multiply that writes no flag;
- ADCX and ADOX (ADX), add-with-carry through CF only and through OF
  only.

Together they run the low halves of a row's products on CF and the high
halves on OF: two independent chains, about three instructions a
product. aws-lc's and OpenSSL's x86-64 bignum assembly is built on them.

What LLVM does with them was measured first (clang/LLVM 18, `-O2
-march=icelake-server`). A four-limb row written with `unsigned
__int128`, and the same row written with `_mulx_u64` and
`_addcarryx_u64`, both compile to 8 `mulx`, 14 `adc` and 0
`adcx`/`adox`. LLVM's flags model has one carry, so it never selects
ADOX, and no IR shape leads it there. The chains have to be written as
instructions.

## Decision

1. **The unit is a row, not a step.** Flags survive only inside one
   inline-asm block, because the compiler may put anything between two
   blocks. The smallest unit whose carries begin and end in registers is
   the row `rp[0..n) += ap[0..n)·b`, which returns the carry word (GMP's
   `mpn_addmul_1`). It is a compiler primitive, `nurl_mac_row(rp, ap, n,
   b)`, emitted into every module like `nurl_mac_w`. One definition
   serves every width: RSA's 16 to 64 limbs and P-256's 4.
2. **The asm handles any n with no width specialisation.** It runs
   n mod 4 single limbs, then a block of four, then blocks of eight.
   Loop control is `lea` + `jrcxz` (no flag written), and addresses are
   base + displacement with the pointers bumped by `lea`.
   - Measured on an i7-11850H for a 16-limb Montgomery multiply: indexed
     addressing un-laminates the micro-fused mulx/adcx/mov and cost 25 %.
   - With pointer bumps, the loop by eight matches a fully unrolled row
     within noise.
   - So there is one asm body and no per-width copies.
3. **ADX is a tier with self-dispatch, not a gate.** The row asks
   `nurl_cpu_has_adx()`: the runtime's CPUID answer (leaf 7 EBX bits 8
   and 19), `readnone`, with `NURL_CPU_ADX=0` taking it away. Without
   ADX it runs a loop of `nurl_mac` steps. That loop is also the row on
   AArch64, `--no-cpu-dispatch` and wasm.
   - AArch64 has one carry flag and nothing like ADOX.
   - `mul`/`umulh`/`adds`/`adcs` is already the best single chain, and
     LLVM emits it from the loop.
   - Unlike the AES/SHA primitives, the row is valid everywhere, so it
     needs no gate and no panic stub.
4. **The asm is per architecture, not per OS.** The block is LLVM IR
   inline asm with register constraints. The calling convention (SysV
   or Win64), object format and assembler syntax are LLVM's concern, so
   one body serves Linux, macOS, FreeBSD and Windows on x86-64.
5. **Algorithms follow the tier.** `std/rsa_mont.nu` uses the row form
   (separated operand scanning) on the ADX tier and keeps FIPS product
   scanning elsewhere.
   - Rows on the single-chain loop are slower than FIPS: at 16 limbs a
     square takes 361 ns against 245 ns.
   - Each tier gets the form that is fastest on it, chosen per call.
   - `crypto_tier_ir.sh` holds both forms to the same golden by running
     with `NURL_CPU_ADX=1` and `=0`.

## Consequences

Measurements are on an i7-11850H.

- **RSA (`std/rsa_mont.nu`):**

  | Operation | Before (FIPS) | After (ADX rows) |
  |---|---|---|
  | 16-limb Montgomery square | 245 ns | 203 ns |
  | 16-limb Montgomery multiply | 322 ns | 211 ns |
  | 32-limb square and multiply | — | 1.65× faster |
  | RSA-2048 signature | 0.79 ms | ~0.62 ms |

- **Remaining gap to aws-lc (0.25 ms on this CPU):** the gap is not
  scalar. aws-lc signs with AVX-512 IFMA (`rsaz_amm52x20_x2_ifma256`),
  which runs both CRT halves in one 52-bit-radix vector multiply. Closing
  it is a vector tier of its own, not more of this one: ADR 0002.
- **Memory traffic:** a row loads and stores `rp` on every row. Kernels
  whose operands fit in registers (P-256's and X25519's four limbs)
  would save that traffic with a fixed-width register form. That is a
  separate primitive, to be measured when those fields move to ADX.
  - **Measured, X25519 (Agora #114):** `nurl_x25519_mulm` /
    `nurl_x25519_sqrm` are that form — the whole 4×4 product and its
    2^256 ≡ 38 fold in one block on the two chains, operands from
    memory, the result in registers. On a Skylake i7-6700T, four
    independent chains: multiply 10.2 ns and square 8.4 ns, against
    24.1 ns for the same product as C over u128. The ladder written on
    them (`std/x25519.nu`, `__scalarmult_k`) runs a step in ~830
    instructions against 1613 for the `nurl_mac` register ladder, and
    X25519 shared takes 35.1 µs against 45.4 µs; keygen 15.0 against
    16.2 µs, where a quarter of the time was the Fermat inversion, a
    serial chain of 265 kernel latencies — since replaced by std/modinv's
    divsteps (#1274: keygen 14.9 → 12.9 µs).
  - Without ADX the same block on `mulq` measured only 4 % on a whole
    Haswell ladder, so that tier keeps the register form. P-256's
    kernels (Agora #108) kept a `mulq` block: there it measured 15.6 ns
    against 28.3 ns for the same CIOS as C.
- **Squaring:** on rows, squaring saves less than its product count
  suggests: 376 products against 512, yet 203 ns against 211 ns. The
  cross-product rows are short, so their per-row setup and the doubling
  pass take most of the difference.
  - **Measured and acted on (Agora #117):** on a Cascade Lake class Xeon
    without IFMA, a 16-limb square split as cross-product rows 97 ns for
    120 products (0.81 ns a product, against 0.50 in full rows), doubling
    and diagonal 33 ns, and reduction 147 ns for 256 products — the
    reduction reloads t after every row, so each row's q = t[k]·n0 waits on
    a store-to-load forward. RSA-2048's halves now run two fixed-width
    blocks instead (`nurl_rsa16_sqrm_adx` / `nurl_rsa16_mulm_adx`, generated
    by `tools/gen_rsa_adx16.py`): every product written out, and the
    reduction blocked eight rows at a time with eight words of t in
    registers and each q parked in the column it zeroes. Square 289 →
    215 ns, multiply 293 → 259 ns, RSA-2048 PSS sign 917 → 729 µs (aws-lc
    648 µs on the same machine). This departs from §1 and §2 for one width
    only, and on purpose. A fixed 16-limb pair is about 4 000
    instructions, so it is not a compiler primitive emitted into every
    module. It is two functions in the C runtime: x86-64 inline asm
    behind the runtime's ADX answer, 0 everywhere else, where the rows
    take over. ThinLTO drops them from programs without RSA. Every other
    width keeps the rows. A blocked reduction of this shape is port-bound
    (ADCX/ADOX share two ports on Intel, llvm-mca); what is left to aws-lc
    is mostly operation count (a 64-bit exponent blind and a 4-bit
    window).
