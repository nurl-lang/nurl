### Fixed

- **`= a g` with `g` a second name of `a`'s own closure env releases nothing** (AGORA-953, part of AGORA-242). With `: g { : i z ( a 1 ) a }`, `g` is a second name of `a`'s env. `= a g` used to release that env as `a`'s old one and then hand `a` the freed env, a heap-use-after-free. The release is now decided by the env's address at run time: the same env stays with its owner, and another closure's env leaves `a`'s own to be released as before. No source changes.
- **A typed `:` binding of a value block whose tail views the block's own local gets a copy** (AGORA-953). `: s e { : String x … ( string_data x ) }` and `: ~ s e { … }`, with the type written, now take the same copy rule as the inferred `: e { … }`. They used to read freed memory once handed back. No source changes.
