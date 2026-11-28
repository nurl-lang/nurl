### Performance

- **Windows: `build.bat` builds `stdlib/runtime.o` with -O2** (AGORA-1039). The line had no optimization flag, so clang built the MSVC-ABI runtime at -O0. Every runtime C function was unoptimized for programs `nurl.bat` links with clang: a repo checkout, or an install without the bundled zig. It was also unoptimized in `nurlc.exe` itself. build.sh and the MinGW object were already -O2. Measured on the clang link path, median of 7 runs:
  - `nurlc` compiling `compiler/nurlc.nu`: 7.16 s → 6.01 s (−16 %).
  - `bench/csv_table_pipeline`: 115 → 75 ms (−34 %). `bench/pq`: 1473 → 1389 ms (−6 %).
  - Cost per call: `float_exp` 21.3 → 3.8 ns, `float_log` 14.3 → 4.4 ns, `string_push_float` 173 → 55 ns, `string_push_int` 109 → 57 ns.
  - `stdlib_hotpath`: `string_build_16` 61 → 33 ns, `vec_push_64` 338 → 281 ns, `sort_32_desc` 119 → 80 ns.

  Peak memory is unchanged (nurlc 187.6 → 187.4 MB). The runtime stays a plain object, not LLVM bitcode as on Linux, because link.exe does every clang link of it on Windows.
