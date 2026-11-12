// diag_defer_in_a_loop_reads_an_earlier_rounds_value.nu — a `^` or a `\`
// above a loop body's `;` runs that defer from the second round on (an
// earlier round armed it), with what that round left: a binding the body
// makes between the two still holds the earlier round's value there
// (agora #670). Refused where that value is gone by then:
//   new_value   a view of an outer binding the round gives a new value
//               above the exit;
//   cleared     an element view of an outer Vec the round clears above it;
//   frees       a defer that frees what the `^` above it hands back;
//   after       a change after the loop to what the last round's view
//               borrows from.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk s p i k → String { : ~ String r ( string_from p ) ( string_push_int r k ) ^ r }

@ new_value i n → i {
    : ~ String x ( mk `new_value: an outer string long enough for the heap ` 0 )
    : ~ i k 0
    ~ < k 3 {
        = x ( mk `new_value: an outer string long enough for the heap ` k )
        ? == k n { ^ 1 } {}
        : s v ( string_data x )
        ; { ( nurl_println v ) }
        = k + k 1
    }
    ^ 0
}

@ cleared i n → i {
    : ~ ( Vec String ) w ( vec_new [String] )
    : ~ i k 0
    ~ < k 3 {
        ( vec_clear [String] w )
        ( vec_push [String] w ( mk `cleared: an element long enough for the heap ` k ) )
        ? == k n { ^ 1 } {}
        : String e ( vec_at [String] w 0 )
        ; { ( nurl_println ( string_data e ) ) }
        = k + k 1
    }
    ^ 0
}

@ frees i n → String {
    : String x ( mk `frees: an outer string long enough for the heap ` 0 )
    : ~ i k 0
    ~ < k 3 {
        ? == k n { ^ x } {}
        ; { ( string_free x ) }
        = k + k 1
    }
    ^ ( mk `frees: fell off, a string long enough for the heap ` 0 )
}

@ after i n → i {
    : ~ String x ( mk `after: an outer string long enough for the heap ` 0 )
    : ~ i k 0
    ~ < k n {
        : s v ( string_data x )
        ; { ( nurl_println v ) }
        = k + k 1
    }
    = x ( mk `after: an outer string long enough for the heap ` 9 )
    ^ k
}

@ main → i {
    ( nurl_println_int ( new_value 1 ) )
    ( nurl_println_int ( cleared 1 ) )
    : String f ( frees 1 )
    ( nurl_println ( string_data f ) )
    ( nurl_println_int ( after 2 ) )
    ^ 0
}
