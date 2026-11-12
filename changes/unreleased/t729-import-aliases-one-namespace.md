### Fixed

- **An import alias leaves struct fields alone** (Agora #729). Behind
  `` $ `m/fld.nu` fl ``, a module declaring `: Pt { i x i y }` beside
  `@ x Pt p → i` had a struct whose field was `fl__x`: an importer's
  `. p x` was "type 'fl__Pt' has no field 'x'". Field names are never
  renamed now — in a struct body, after a `.`'s object, in a field store,
  a nested path or an `inout` field argument — and where the word after a
  `.` is an index instead (`. buf n`, `n` a name of the module), the
  compiler reads it as the module's name, as the module's own text meant.
- **A module imported under a second alias is the same module** (Agora
  #694). `$ … m` then `$ … n` (in one file or a library and its user)
  skipped the second import without a word, and its first use failed as
  "use of undefined identifier" for the binding. A later alias now reads
  as the first spelling (`n::Point` is `m::Point`; after a plain import it
  is `Point`); a plain import after an aliased one is refused at the
  import, naming both spellings and what to write instead.
- **A function and a type cannot share a name** (Agora #728). `@ Pt` beside
  `: Pt { … }` or `: Pt [A] { … }` compiled until a call `( Pt 4 )`, which
  read as the type ("argument 1 … has type 'Pt'", "expected a type, found
  '4'"). The later of the two declarations is refused, naming the first.
- **An aliased type used above its import follows the "declared LATER"
  rule** (Agora #730), as a plainly imported one does, spelled `geo::Pt`:
  it was accepted without a field read and refused as "type 'geo__Pt' has
  no field 'x'" with one. Diagnostics spell every aliased name the way the
  program writes it (`geo::Pt`, not `geo__Pt`).

### Performance

- **The alias rewrite is linear and made once per import.** It lexed the
  file and then rebuilt it one byte at a time with a string concatenation
  each (quadratic in the file's size), in each of the three passes that
  read an aliased import; it now walks the tokens once, copies the text
  between them, and every pass shares the result.
