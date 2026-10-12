// `( mem_replace [T] place x )` puts x into the place and hands back what it
// held, owned: a mutable binding, a field of one, and a field through a
// pointer parameter (an `inout` argument through a pointer, which needs no `~`).
// `( mem_addr p )` of an `inout` parameter is the caller's place. Nothing is
// dropped twice and nothing leaks (the sanitizer run checks).
$ `stdlib/core/string.nu`
$ `stdlib/core/box.nu`
$ `stdlib/core/mem.nu`

: Rec { String out i n }

unsafe @ take_out * Rec r → String {
    ^ ( mem_replace [String] . r out ( string_from `left in place` ) )
}

// mem_addr of an inout parameter: the caller's i, written through.
unsafe @ bump inout i x → v {
    : *i p ( mem_addr x )
    = . p 0 + . p 0 1
}

unsafe @ main → i {
    : ~ String s ( string_from `first value` )
    : String old ( mem_replace [String] s ( string_from `second value` ) )
    ( nurl_println ( string_data old ) )
    ( nurl_println ( string_data s ) )

    : ~ Rec rec @ Rec { ( string_from `a field value` ) 1 }
    : String got ( mem_replace [String] . rec out ( string_from `its replacement` ) )
    ( nurl_println ( string_data got ) )
    ( nurl_println ( string_data . rec out ) )

    : ( Box Rec ) b ( box_new [Rec] @ Rec { ( string_from `inside the box` ) 3 } )
    : String t ( take_out # *Rec ( box_ptr [Rec] b ) )
    ( nurl_println ( string_data t ) )
    : *Rec bp # *Rec ( box_ptr [Rec] b )
    ( nurl_println ( string_data . bp out ) )

    : ~ i k 41
    ( bump k )
    ( nurl_println_int k )
    ^ 0
}
