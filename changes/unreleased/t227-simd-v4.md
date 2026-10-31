### Added

- **`simd v4 @ f`: a third clone for x86-64-v4** (Agora #227, grammar
  v2.12). `simd` takes an optional level word. `simd v4` compiles the
  body a third time for x86-64-v4 (AVX-512 F/BW/CD/DQ/VL on top of v3),
  beside the baseline and x86-64-v3 clones. The dispatcher picks it where
  the CPU has it: Skylake-SP, Ice Lake and later Intel servers, and
  Zen 4 and later. The code keeps v128/v256 vectors, but gets 32
  registers, VPROLD and VPTERNLOG. A bare `simd` is unchanged. Any other
  word after `simd` is an error that names the one level there is. The
  runtime's answer is `nurl_cpu_x86_v4()`. `NURL_CPU_V4=0` takes it away,
  and so does `NURL_CPU_V3=0`. Inside each clone, a `nurl_cpu_x86_v4()`
  whose answer its dispatcher already knows is a constant, as
  `nurl_cpu_x86_v3()` already was. nurlfmt keeps the level on the
  prefix's line, and the language server indexes `simd v4` functions.

### Performance

- **ChaCha20-Poly1305 is 19 % faster on AVX-512 CPUs** (Agora #227).
  ChaCha20's eight-block pass is `simd v4`. Every lane rotate is one
  VPROLD there; the v3 clone rotates by 16 and 8 with a byte shuffle,
  and by 12 and 7 with shift, shift, or. The 32 registers keep the
  eight-block state off the stack: 12 ymm stack accesses in the
  function, down from 110. On a Sapphire Rapids class Xeon, best of six
  interleaved runs, 16 KB:

  | | ChaCha20 | Seal |
  |---|---|---|
  | x86-64-v3 clone (before; `NURL_CPU_V4=0`) | 7.27 µs | 10.33 µs |
  | x86-64-v4 clone | 5.24 µs | 8.40 µs |
  | aws-lc | | 9.34 µs |

  `chacha20poly1305_cpu_tier()` now says `avx512` on these CPUs.

- **The third clone costs no compile time**: Poly1305's four-way kernel
  now asks `nurl_cpu_x86_v3()` itself and consumes nothing without v3, as
  its callers already ensured. In its baseline clone that answer is the
  constant 0, so the 11.5 KB of v256 arithmetic in SSE2 halves, which
  never ran, is now a bare return. A program that imports
  `chacha20poly1305` compiles as fast as before (LLVM, median of 11:
  1223 ms before, 1230 ms after). Its object is 6 KB smaller.
