### Changed

- `nurlc --emit-core`: a loop whose condition is a literal that is true (`~ T {`, `~ 1 {`) prints `loopcond T`. The loop is left only by a `break` or a `^`, which the ownership engine has to know to say what holds after it. Nothing changes without `--emit-core` (AGORA-859).
