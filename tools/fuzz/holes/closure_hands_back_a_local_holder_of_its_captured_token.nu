// closure_hands_back_a_local_holder_of_its_captured_token: a closure literal sets a field of a local struct to a captured view-holder and hands the struct back.
// Closed: a closure's capture or inout parameter that holds views (`cv_`) stands for itself in `bck_sx_name`, so assigning a field of a local holder from a capture records the capture in `vds_` and `bck_ret_view_check` refuses the return (h220; agora #473).
// main a3be3e7c: accepted; AddressSanitizer: heap-use-after-free.
// map: §7.5 | A2 | rejected | h220 | agora #473: a closure literal sets a field of a local struct to a captured view-holder and hands it back
$ `stdlib/core/string.nu`

: Tok { s w }
: Hold { Tok t }

@ call0 ( @ Hold ) f → Hold { ^ ( f ) }

@ leak → Hold {
    : String s ( string_from `hello world from freed string buffer on heap` )
    : Tok ct @ Tok { ( string_data s ) }
    ^ ( call0 \ → Hold {
        : ~ Hold h @ Hold { @ Tok { `ok` } }
        = . h t ct
        ^ h
    } )
}

@ main → i {
    : Hold out ( leak )
    ( nurl_println . . out t w )
    ^ 0
}
