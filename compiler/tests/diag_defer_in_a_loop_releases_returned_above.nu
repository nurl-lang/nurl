// diag_defer_in_a_loop_releases_returned_above.nu — a `^` above a loop
// body's `;` runs that defer from the second round on (an earlier round
// armed it), so a defer that releases what the `^` hands back, or gives a
// field of it a new value, is refused there as it is below the `;`
// (agora #655, #165).

$ `stdlib/core/string.nu`

: Q { String name String tag }

@ mk s t → String { ^ ( string_from t ) }

@ frees_it i n → String {
    : String x ( mk `one` )
    : ~ i k 0
    ~ < k 3 {
        ? == k n {
            ^ x
        } {}
        ; { ( string_free x ) }
        = k + k 1
    }
    ^ ( mk `two` )
}

@ replaces_a_field i n → Q {
    : ~ Q q @ Q { ( mk `three` ) ( mk `four` ) }
    : ~ i k 0
    ~ T {
        ? == k n {
            ^ q
        } {}
        ; { = . q name ( mk `five` ) }
        = k + k 1
    }
}

@ main → i {
    : String a ( frees_it 1 )
    : Q b ( replaces_a_field 1 )
    ( nurl_println ( string_data a ) )
    ( nurl_println ( string_data . b tag ) )
    ^ 0
}
