### Fixed

- **An `inout` parameter given a value block that ends in a call takes the call's answer** (Agora #628). `@ set inout String p String o → v { = p { ( string_concat o o ) } }` leaked the caller's old value and one result per call; `= p ( string_concat o o )` was already clean. The inout store path asks the block's tail call, as the `:` binding of one does (#613). With #668's routing, a join of a value block's locals handed to a `sink` no longer leaks the local the join did not select.
