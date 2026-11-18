### Fixed

- **A view of a `??` payload handed out of its arm now ends with the option it came from** (AGORA-842 part 1; seven AGORA-428 shapes). In `: ( Slice i ) v ?? o { T q → ( slice_from_vec [i] q ) F → … }`, `v` borrowed from nothing, so replacing, growing or releasing `o` afterwards, or returning `v`, read freed memory. That is refused now, including when the payload is grown through a closure, a generic callee or a callee's own match. Reading `v` while `o` is unchanged is still accepted.
