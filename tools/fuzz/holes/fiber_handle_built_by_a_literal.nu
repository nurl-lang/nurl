// fiber_handle_built_by_a_literal: `( fiber_join @ Fiber { p } )` with `p` any address: the join
// waited on and freed whatever `p` pointed at.
// Closed: Fiber is a sealed `raw` struct, so only unsafe code builds one
// (agora #168).
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
// map: §3.3d | B | rejected | h615 | `( fiber_join @ Fiber { ( string_data k ) } )`: the join waited on and freed any address; Fiber is a sealed `raw` struct (agora #168).
$ `stdlib/core/string.nu`
$ `stdlib/std/async.nu`

@ main → i {
    : String k ( string_from `xxxxxxxx` )
    ( fiber_join @ Fiber { ( string_data k ) T } )
    ^ 0
}
