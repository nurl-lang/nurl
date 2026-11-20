// slice_field_read_out_of_a_drop_temporary_runs_clean: `( ln . ( mkh ) s )`, `: [i x . ( mkh ) s`, `. . ( mkh ) s length` and `( ln . @ H { ( mk ) 8 } s )` with H's own `% Drop`: an owned slice field read out of a temporary whose drop must see it
// Closed (agora #895's review): under a `% Drop` of the struct's own the slice is not taken out (the drop would see it gone); the temporary gets an owner for the rest of the scope (h233, h329) and the slice is read out of it, lent, as a String field is, and the temporary and its drop run once at the scope's end.
// main 08e56f54: AddressSanitizer: heap-use-after-free (h232 released the struct under the slice); with github#2108's first take-out, LeakSanitizer: the temporary leaked and its drop never ran.
// map: §7.6 | A2 | runs-clean | - | agora #895: an owned slice field read out of a `% Drop` struct temporary, handed to a call, bound and read for its length, of a call's result and of a literal
: H { [i s i n }

% Drop H { @ drop H h → v { ( nurl_println_int . h n ) } }

@ mk → [i { ^ [i | 1 2 3] }
@ mkh → H { ^ @ H { ( mk ) 7 } }
@ ln [i t → i { : ~ i k 0 ~ x t { = k + k x } ^ k }

@ main → i {
    ( nurl_println_int ( ln . ( mkh ) s ) )
    : [i x . ( mkh ) s
    ( nurl_println_int ( ln x ) )
    ( nurl_println_int . . ( mkh ) s length )
    ( nurl_println_int ( ln . @ H { ( mk ) 8 } s ) )
    ^ 0
}
