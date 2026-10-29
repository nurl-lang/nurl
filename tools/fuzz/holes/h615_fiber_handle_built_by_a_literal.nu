// H615: `( fiber_join @ Fiber { p } )` with `p` any address: the join
// waited on and freed whatever `p` pointed at.
// Closed: Fiber is a sealed `raw` struct, so only unsafe code builds one
// (agora #168).
// v0.80.0: accepted; AddressSanitizer reported heap-buffer-overflow.
$ `stdlib/core/string.nu`
$ `stdlib/std/async.nu`

@ main → i {
    : String k ( string_from `xxxxxxxx` )
    ( fiber_join @ Fiber { ( string_data k ) T } )
    ^ 0
}
