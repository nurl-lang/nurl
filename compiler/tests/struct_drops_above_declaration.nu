// struct_drops_above_declaration.nu — agora #772: structs that own heap
// storage, nested by value, with a `% Drop` of their own, made, replaced
// and dropped in functions above their declarations: each value is
// released once, as when the declarations come first (the leak gate and
// the sanitizer corpus run this file).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk i k → Bag {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a` ) )
    ^ @ Bag { ( string_from `hello` ) v @ Inner { k ( string_from `in` ) } }
}

@ show Bag b → i { ^ + ( string_len . b name ) . . b inner n }

@ main → i {
    : Bag b ( mk 5 )
    : ~ Bag c ( mk 6 )
    = c ( mk 7 )
    = . c name ( string_from `zz` )
    : i t + ( show b ) ( show c )
    : ~ Noisy z @ Noisy { 1 }
    = z @ Noisy { 2 }
    ( nurl_println_int t )
    ^ - t 19
}

: Inner { i n String s }

: Bag { String name ( Vec String ) items Inner inner }

: Noisy { i v }

% Drop Noisy { @ drop Noisy x → v { ( nurl_println_int . x v ) } }
