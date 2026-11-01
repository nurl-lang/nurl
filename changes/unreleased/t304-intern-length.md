### Fixed

- **nurlc's string interner compares an entry's length before its bytes,
  so a lookup never reads past a stored string** (Agora #304, test
  intern_collision_lengths). Every name and type the compiler's symbol
  tables hold is stored once, in an arena, behind a 31-bit hash. A lookup
  that met an entry with its key's hash compared the key's n bytes before
  it checked that the entry was n bytes long. For a shorter entry at the
  end of its arena chunk, that read past the chunk: a heap-buffer-overflow
  that the sanitized compiler reported on a branch whose stdlib happened to
  make two names of different lengths collide. And an entry with a NUL
  inside could match a shorter key. Each entry now carries its length in
  place of the hash, which the table recomputes from the bytes only when
  it grows. So a probe compares the length, then exactly that many bytes,
  in the same memory as before. Two names of different lengths with one
  hash, `icco0q` and `icl_aaaa2g_x`, are now a corpus test. With every
  interned string in a chunk of its own size, the old compiler fails it
  under ASan (READ of size 12) and the fixed one passes.
