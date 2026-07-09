// div_by_zero_recover.nu — integer division / remainder by a runtime-zero
// divisor must PANIC (not silently trap / hit LLVM UB), and the panic must be
// catchable via recover carrying the "division by zero" / "remainder by zero"
// message. Regression for the C2 div-by-zero guard. Normal division past the
// recover boundary must still work.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

@ divide i a i b → i { ^ / a b }

@ modulo i a i b → i { ^ % a b }

@ main → i {
    : i z 0
    : !v PanicInfo r1 ( recover \ → v { : i _x ( divide 10 z ) } )
    ?? r1 {
        T _ → ( nurl_print `div: no panic (unexpected!)\n` )
        F p → {
            ( nurl_print `div: caught msg=` )
            ( nurl_print ( string_data . p msg ) )
            ( nurl_print `\n` )
            ( panic_info_free p )
        }
    }
    : !v PanicInfo r2 ( recover \ → v { : i _y ( modulo 10 z ) } )
    ?? r2 {
        T _ → ( nurl_print `mod: no panic (unexpected!)\n` )
        F p → {
            ( nurl_print `mod: caught msg=` )
            ( nurl_print ( string_data . p msg ) )
            ( nurl_print `\n` )
            ( panic_info_free p )
        }
    }
    ( nurl_print `ok: ` ) ( nurl_print_int / 20 4 ) ( nurl_print `\n` )
    ^ 0
}
