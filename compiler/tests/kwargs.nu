// kwargs.nu — keyword arguments: default parameter values + named call
// arguments (in any order, mixed with positional). Covers void and
// value-returning callees.

// Two trailing parameters carry defaults.
@ box s label i width = 10 s fill = `-` → v {
    ( nurl_print label ) ( nurl_print `:` )
    : ~ i i 0
    ~ < i width { ( nurl_print fill ) = i + i 1 }
    ( nurl_print `\n` )
}

@ sum3 i a i b = 100 i c = 1000 → i { ^ + + a b c }

@ main → i {
    ( box `a` )                    // width=10 fill=-  → ----------
    ( box `b` 3 )                  // fill=-           → ---
    ( box `c` 3 `*` )              // all positional   → ***
    ( box label: `d` fill: `=` )   // named, reordered, width default → ==========
    ( box `e` fill: `#` width: 5 ) // positional + named, reordered   → #####

    ( nurl_print ( nurl_str_int ( sum3 1 ) ) ) ( nurl_print `\n` )          // 1+100+1000 = 1101
    ( nurl_print ( nurl_str_int ( sum3 1 2 ) ) ) ( nurl_print `\n` )        // 1+2+1000   = 1003
    ( nurl_print ( nurl_str_int ( sum3 1 c: 5 ) ) ) ( nurl_print `\n` )     // 1+100+5    = 106
    ( nurl_print ( nurl_str_int ( sum3 c: 7 a: 2 b: 3 ) ) ) ( nurl_print `\n` ) // 2+3+7  = 12
    ^ 0
}
