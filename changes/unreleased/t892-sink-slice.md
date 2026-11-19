### Fixed

- **A `sink` slice parameter is released by its callee** (AGORA-892). `( eat ( mk ) )` with `@ eat sink [i a → i { … }` leaked the slice: the caller handed it over and the callee never released it. The callee now owns a `sink [T` parameter from entry on, like a local bound to a fresh slice, and releases it on every way out unless it moves it on (returns it, hands it to another `sink`, stores it into an owner), a panic's unwind included.

### Changed

- **A slice binding can be handed to a `sink` parameter.** `: [i t ( mk )  ( eat t )` was refused as "not yet supported"; it now moves the slice to the callee as a Vec binding does, and `t` is dead after the call. A borrowed `[T` parameter handed on to a `sink` makes its function take the slice over too, as for a Vec. No migration is needed: the form was refused before.
