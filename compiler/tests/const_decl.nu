// const_decl with all literal types

: ~ i MAX_CONN 100
: f PI 3.14159
: s GREETING `hello`
: b VERBOSE T

@ main → i {
    ( nurl_print `const_decl all types test...\n` )

    ( nurl_print `MAX_CONN: ` )
    ( nurl_print ( nurl_str_int MAX_CONN ) )
    ( nurl_print `\n` )

    ( nurl_print `PI: ` )
    ( nurl_print ( nurl_str_float PI ) )
    ( nurl_print `\n` )

    ( nurl_print `GREETING: ` )
    ( nurl_print GREETING )
    ( nurl_print `\n` )

    ( nurl_print `VERBOSE: ` )
    ( nurl_print ? VERBOSE `on` `off` )
    ( nurl_print `\n` )

    // Mutability test — const_decl values are mutable globals
    = MAX_CONN + MAX_CONN 1
    ( nurl_print `MAX_CONN after increment: ` )
    ( nurl_print ( nurl_str_int MAX_CONN ) )
    ( nurl_print `\n` )

    ^ 0
}
