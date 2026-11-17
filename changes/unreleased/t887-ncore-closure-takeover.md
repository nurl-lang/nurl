### Changed

- **The reference ownership checker in tools/ncore follows a closure that takes a capture over** (AGORA-887). Take a value that cannot be copied, captured by a closure that may leave its frame. The closure's environment takes that value over, as the compiler does, and a by-value parameter captured that way is consumed by its function. The checker now refuses one faulting program it accepted and accepts two safe ones it refused.
