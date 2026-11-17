### Changed

- **The ownership engine (`nurlc --engine`) and tools/ncore follow an option parameter's payload handed back through a binding** (AGORA-887). Take `: String r ?? o { T s → s F → ( mk ) }  ^ r`: the function now takes the caller's argument, as it already did for `^ ?? o {…}`. The compiler's checker already refused the caller's later use of `o`; the engine and the reference checker now refuse it too.
