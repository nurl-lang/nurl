### Changed

- **The formal proof covers a call that hands a view to a function changing the elements of its `inout` parameter** (AGORA-909, github#2041). A2 now has a witness for `( g vv s )` where `g` pushes through `( vec_at vv 0 )` of its `inout` parameter and `s`, a view of another value, is read after the call: `A2/InoutViewArgWitness.lean` types it, memory safe and leak-free. No rule changed: the push is through a borrow of the function's own `inout` parameter, so the call asks nothing of the view. A view of `vv` itself stays refused. NURL source is unchanged.
