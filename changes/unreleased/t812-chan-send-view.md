### Fixed

- **A view sent on a channel no longer reaches the receiving thread after its owner is gone** (AGORA-812). `( chan_send [s] ch ( string_data m ) )`, or a `Job` whose closure captured a view, is now refused, just as a spawned closure holding a view already was. The receiving thread used to read freed memory once `m` was released.

### Changed

- **Breaking: a value sent on a channel may not hold a view of this side's storage**, even when the channel is only used on one thread. Send an owned value instead: a `String` rather than its `s`, a Vec of owned values, or a share through `Arc`. Views of string literals are still allowed. Migration: the oauth package's `with_oidc_scope` now takes `sink String scope`, because its route runs on the HTTP server's worker threads. oauth goes to 0.3.0, and its example and README pass `( string_from … )`. Wrappers that hand a parameter on to `chan_send` are checked the same way, so a caller's view does not cross through them either.
