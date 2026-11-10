// diag_call_named_twice.nu — a parameter given twice: positionally and
// then by name (`( add 1 2 x: 3 )`). The named path used to keep the later
// value in silence; it now refuses the call and names the argument.
@ add i x i y = 2 → i { ^ + x y }

@ main → i {
    : i r ( add 1 2 x : 3 )
    ^ r
}
