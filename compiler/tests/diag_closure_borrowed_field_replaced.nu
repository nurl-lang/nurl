// diag_closure_borrowed_field_replaced.nu — a closure read out of a struct's
// field borrows from the struct (its env lives there): replacing the field
// frees that env, and calling the closure after it is rejected (h283).

$ `stdlib/core/string.nu`

: S { ( @ i i ) f }

@ main → i {
    : String a ( string_from `abcdefghijklmnopqrstuvwxyz` )
    : ( @ i i ) f0 \ i x → i { ^ + x ( string_len a ) }
    : ~ S s @ S { f0 }
    : ( @ i i ) g . s f
    = . s f \ i x → i { ^ x }
    ( nurl_println_int ( g 1 ) )
    ^ 0
}
