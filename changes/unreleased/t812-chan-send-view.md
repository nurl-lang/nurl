### Fixed

- **A view sent on a channel no longer reaches the receiving thread after its owner is gone** (AGORA-812). `( chan_send [s] ch ( string_data m ) )`, or a `Job` whose closure captured a view, is now refused, just as a spawned closure holding a view already was. The receiving thread used to read freed memory once `m` was released.

### Changed

- **Breaking: a value sent on a channel may not hold a view of this side's storage**, even when the channel is only used on one thread. Send an owned value instead: a `String` rather than its `s`, a Vec of owned values, or a share through `Arc`. Views of string literals are still allowed. Migration: no in-repo code sent views on channels.
