### Changed

- **The reference ownership checker in tools/ncore keeps a lend nurlc hands over as it is** (AGORA-887). A call's result that lends a local, given to a binding by `=`, is that lend and not a copy, as the compiler's engine reads it. A copyable `inout` parameter is still given a copy. The checker now refuses one faulting program it accepted (a value block's local lent through a call in a loop) and accepts two safe ones it refused. It newly accepts no faulting program.
