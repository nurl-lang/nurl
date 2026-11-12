// parameter_handed_back_through_twelve_functions_declared_below: `@ f12 String p → String { ^ ( f11 p ) }` … `@ f0 String p → String { ^ p }`, each callee declared below its caller; `: String s ( f12 x )` and both read
// Closed: the walks that ask whether a function lends its argument follow the callees it hands back as a worklist with the set already asked, where a budget of eight answered "owned" (agora #721).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | runs-clean | - | agora #721: a parameter handed back through twelve functions declared bottom-up is lent
$ `stdlib/core/string.nu`

@ f12 String p → String { ^ ( f11 p ) }

@ f11 String p → String { ^ ( f10 p ) }

@ f10 String p → String { ^ ( f9 p ) }

@ f9 String p → String { ^ ( f8 p ) }

@ f8 String p → String { ^ ( f7 p ) }

@ f7 String p → String { ^ ( f6 p ) }

@ f6 String p → String { ^ ( f5 p ) }

@ f5 String p → String { ^ ( f4 p ) }

@ f4 String p → String { ^ ( f3 p ) }

@ f3 String p → String { ^ ( f2 p ) }

@ f2 String p → String { ^ ( f1 p ) }

@ f1 String p → String { ^ ( f0 p ) }

@ f0 String p → String { ^ p }

@ main → i {
    : String x ( string_from `a string long enough to live on the heap` )
    : String s ( f12 x )
    ( nurl_println ( string_data s ) )
    ( nurl_println ( string_data x ) )
    ^ 0
}
