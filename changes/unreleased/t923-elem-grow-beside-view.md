### Fixed

- **A view of an argument's element can no longer be handed beside it to a callee that grows that element** (AGORA-923). `( g vv s )`, where s is a slice of `( vec_at vv 0 )` and g pushes through `( vec_at vv 0 )` of its borrowed `vv` before reading s, was accepted and read freed memory. It is refused now: pass a copy that owns its data (`slice_to_vec`), or read what s reaches inside the callee. A view of an unrelated `Vec` handed beside it is still accepted.
