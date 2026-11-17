// closure_run_in_place_reads_a_calls_lend_of_a_local_runs_clean:
// AGORA-899 neighbour: accepted - the closure stays in the frame, so it captures x as a borrow and nothing takes x over
// map: §7.5 | A2 | runs-clean | - | AGORA-899: the take-over rule must not refuse a closure that stays
$ `stdlib/core/string.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ pick R a → R { ^ a }

@ main → i {
    : R a ( mk `a value long enough for the heap buffer, surely, yes` )
    : R x ( pick a )
    : ( @ v ) g \ → v { ( nurl_println ( string_data . x s ) ) }
    ( g )
    ( nurl_println ( string_data . a s ) )
    ^ 0
}
