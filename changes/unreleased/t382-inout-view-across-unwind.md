### Fixed

- **An `inout` parameter may not view a value of its function across a call that may panic** (AGORA-382). `= w @ W { ( string_data b ) }`, with `b` a local, followed by anything that may panic (`( vec_at xs k )` past the end, `( panic … )`, any call) before `w` is pointed back, handed `w` to a `recover` caller still viewing `b`'s freed buffer. That is refused now at the call. Point `w` back before the call, or give it a copy that owns its data. A view of what the caller passed in is unaffected.
