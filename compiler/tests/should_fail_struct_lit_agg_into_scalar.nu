// A struct VALUE in a scalar field slot of a positional struct literal must
// be a compile error with a source location, not an LLVM "insertvalue
// operand and field disagree in type" a stage later. The way this happens
// in practice: a positional literal written against an older layout of the
// struct — here `S` gained `a` in front, so `( vec_new [u] )` now lands in
// the `i` slot and `1` in the `Vec` slot (found by http2_stream_prune.nu's
// hand-built H2Connection when the connection grew a field).
$ `stdlib/core/vec.nu`

: S { i a ( Vec u ) b i c }

@ main → i {
    : S s @ S { ( vec_new [u] ) 1 }
    ^ . s c
}
