// map: §7.6 | A2 | rejected | - | AGORA-384: a program's own generic handle's `Holder_drop` hook reads a view field whose source is declared after the holder
// AGORA-384 (closed): refused - a drop hook of the program's own may read the views its value holds, as a `% Drop` may (main 2c54f01f: accepted, heap-use-after-free)
$ `stdlib/core/string.nu`

: Holder [T] { s name T x }

@ Holder_drop [T] sink ( Holder T ) h → v { ( nurl_println . h name ) }

@ main → i {
    : ~ ( Holder i ) h @ ( Holder i ) { `literal` 1 }
    : String b ( string_from `a string younger than the holder, freed before its hook runs` )
    = h @ ( Holder i ) { ( string_data b ) 2 }
    ^ 0
}
