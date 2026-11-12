// generic_identity_handed_back_through_twelve_functions: a generic `@ f12 [T] T p → T { ^ ( f11 [T] p ) }` … `@ f0 [T] T p → T { ^ p }` called with a String
// Closed: as for the plain chain: no depth budget in the lend walks (agora #721).
// main 3b63ee3b: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.8 | A2 | runs-clean | - | agora #721: a generic identity chain of twelve hands its argument back lent
$ `stdlib/core/string.nu`

@ f12 [T] T p → T { ^ ( f11 [T] p ) }

@ f11 [T] T p → T { ^ ( f10 [T] p ) }

@ f10 [T] T p → T { ^ ( f9 [T] p ) }

@ f9 [T] T p → T { ^ ( f8 [T] p ) }

@ f8 [T] T p → T { ^ ( f7 [T] p ) }

@ f7 [T] T p → T { ^ ( f6 [T] p ) }

@ f6 [T] T p → T { ^ ( f5 [T] p ) }

@ f5 [T] T p → T { ^ ( f4 [T] p ) }

@ f4 [T] T p → T { ^ ( f3 [T] p ) }

@ f3 [T] T p → T { ^ ( f2 [T] p ) }

@ f2 [T] T p → T { ^ ( f1 [T] p ) }

@ f1 [T] T p → T { ^ ( f0 [T] p ) }

@ f0 [T] T p → T { ^ p }

@ main → i {
    : String x ( string_from `a string long enough to live on the heap` )
    : String s ( f12 [String] x )
    ( nurl_println ( string_data s ) )
    ( nurl_println ( string_data x ) )
    ^ 0
}
