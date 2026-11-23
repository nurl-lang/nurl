### Fixed

- **`= a g` with `g` a second name of `a`'s own closure env releases nothing** (AGORA-953, part of AGORA-242). With `: g { : i z ( a 1 ) a }`, `g` is a second name of `a`'s env. `= a g` used to release that env as `a`'s old one and then hand `a` the freed env, a heap-use-after-free. The release is now decided by the env's address at run time: the same env stays with its owner, and another closure's env leaves `a`'s own to be released as before. No source changes.
