### Changed

- **The ownership engine (`nurlc --engine`) and tools/ncore follow a returned literal that holds a part of a parameter** (AGORA-907). Take `^ @ ?N { T ( box_get [N] b ) }`, where `b` is read out of the parameter. The compiler hands such a literal back without copying its payload. The core IR now marks it, and both checkers read it as a lend of the parameter's part. `= o ( npick o ( tail o ) k )`, which may hand back `o` itself or that part, is refused by both, as the compiler's checker already refuses it.
