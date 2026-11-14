### Added

- `nurlc --engine`: the ownership engine of `docs/dev/PROPOSAL_CORE_IR.md` (stage S2), in shadow. It is `--emit-core`, and after the IR what the engine in the compiler says of the module: `eng err` findings and an `eng verdict` line. It reads the core IR the walk builds and gives the reference checker's (`tools/ncore`) verdict on every hole probe, every example and every valid compiler test; it accepts the compiler's own source, in fewer instructions than the borrow walk it is to replace. An ordinary compile is unchanged: the walk still decides. `docs/dev/CORE_IR.md` §7; `tools/ncore/engcmp.py` compares the two (AGORA-863).

### Fixed

- `tools/ncore` (the reference checker): a callee that gives its `inout` parameter a new value on some of its paths only was taken to have replaced it, so a holder whose view's source ended after the call was read unnoticed; a closure run under `recover` was taken to have run to its end. A summary's effect now says what may happen: a parameter that may go back holding what it held keeps it at the call, and a closure run where a panic in it is caught may stop anywhere. Two probes (AGORA-863, AGORA-859).
