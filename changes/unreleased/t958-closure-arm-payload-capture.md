### Fixed

- **A closure that a `??` arm builds over its payload, bound by `:`, can no longer outlive the matched value** (AGORA-958). `: c ?? o { T s → \ → i { ^ ( string_len s ) } F → … }` followed by `^ c` (or `= outer c`), with `o` a local, handed out a closure reading `o`'s freed payload. It is refused now, as a closure over a local is. Return the join directly (`^ ?? o { T s → \ … }`), which copies the payload into the closure.
