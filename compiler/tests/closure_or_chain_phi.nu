// Regression: a short-circuit `|` chain inside a CLOSURE must phi over a block
// that exists in the CLOSURE's function. The closure is lifted into its own
// `define` whose first block is `entry`; it used to inherit the enclosing
// function's current-block name, so the first phi named a block from another
// function (`phi i1 [ 1, %end_3 ]`) and clang rejected the module with
// "use of undefined value". The enclosing function must leave `entry` first,
// otherwise the stale name coincides with the closure's own entry block and
// the bug hides.

$ `stdlib/core/string.nu`

: Req { String path }

@ run ( @ i Req ) f Req r → i { ^ ( f r ) }

@ main → i {
    : ~ i seed 0
    ? > ( nurl_str_len `x` ) 0 { = seed 1 } {}
    : ( @ i Req ) h \ Req r → i {
        : s rp ( string_data . r path )
        ? | != 0 ( nurl_str_eq rp `/mcp` ) | != 0 ( nurl_str_eq rp `/` ) != 0 ( nurl_str_eq rp `/mcp/` ) { ^ 1 } {}
        ^ 0
    }
    : Req a @ Req { ( string_from `/mcp` ) }
    : Req b @ Req { ( string_from `/other` ) }
    : Req c @ Req { ( string_from `/` ) }
    ( nurl_println_int ( run h a ) )
    ( nurl_println_int ( run h b ) )
    ( nurl_println_int ( run h c ) )
    ( nurl_println_int seed )
    ( string_free . a path ) ( string_free . b path ) ( string_free . c path )
    ^ 0
}
