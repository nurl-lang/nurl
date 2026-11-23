### Performance

- **nurlc holds its input file once and compares a row's field in place** (AGORA-972). Compiling `compiler/nurlc.nu`, nurlc now peaks 6.7 MB lower (210,069 → 203,412 KB, mean of eight runs, −3.2 %) and executes 58.7 M fewer instructions (−0.21 %). Its output is byte-identical: the compiler's own source and all 7,277 files of the tree sweep compile exactly as before. Two changes:
  - A source read hands back the snapshot table's own copy, valid for the whole compile. Before, the input file was held twice: once as that snapshot, and once as `main`'s copy from the join with the `--stdin` arm. A `--stdin` overlay is now written into the table for the input's path, so every read sees it as before.
  - The borrow walk compares a row's kind or mark with a literal byte by byte (`bck_field_is`). Before, it copied the field first, which meant a malloc, a copy and a free at each of 57 sites.

  Both are safe code. `compiler_read_source` and `bck_field_id` were `unsafe` and no longer are, and the raw-pointer aliases `g_input_source` and `g_input_key` are gone. No program's results, drops or diagnostics change.
