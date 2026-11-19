### Changed

- **The ownership engine (`nurlc --engine`) and tools/ncore refuse a per-run lend handed to a consumer** (AGORA-902). Take `: R x ( pick a F )`, where `pick` hands its parameter back on some runs, and `R` has no copy. Handing `x` to a `sink` parameter, or to a closure that takes it over, is now refused, as the compiler's checker already did. Before, both accepted it whenever the call might also hand over a value of its own.
