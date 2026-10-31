### Changed

- **Compiling a program with many calls no longer spends a tenth of its
  time copying lists** (Agora #237). The module-end passes that emit the
  ownership flag constants (`emit_sink_flags`, `mem_emit_arg_flags`,
  `mem_emit_dtor_flags`, `mem_emit_env_flags`, `mem_emit_scratch_flags`)
  walked their lists with `str_first_word` / `str_skip_word`, and each
  step copied the whole rest of the list: quadratic in the number of call
  sites. They walk with a cursor now. `nurlapi/main.nu` compiles in 13 %
  fewer instructions, with byte-identical output.
