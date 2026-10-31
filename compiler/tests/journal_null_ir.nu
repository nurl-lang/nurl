// journal_null_ir.nu — the program journal_null_ir.sh reads the IR of: a
// raw-pointer accessor (vec_data), a raw-pointer binding of its result, and
// a function handing back an owned string, all inside a recover extent so
// the panic journal is live (agora #282).
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/bytes.nu`
$ `stdlib/std/panic.nu`

// Writes n bytes through a raw pointer: raw code vouches for the bounds.
unsafe @ fill ( Vec u ) out i n → v {
    ( vec_reserve [u] out n )
    : ~ * u dst ( vec_data [u] out )
    : ~ i k 0
    ~ < k n {
        = . dst k # u 65
        = k + k 1
    }
}

// Hands back a raw string bound first (the frame table holds it).
@ shout s name → s {
    : s r ( nurl_str_cat name `!` )
    ^ r
}

@ main → i {
    : ( Vec u ) out ( vec_new [u] )
    : !v PanicInfo r ( recover \ → v {
        ( fill out 4 )
        ( bytes_push_int out 7 )
    } )
    : s g ( shout `world` )
    ( nurl_println g )
    ( nurl_println_int ( vec_len [u] out ) )
    ^ 0
}
