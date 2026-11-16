// closure_that_only_reads_its_captured_drop_parameter_run_by_a_runner:
// AGORA-869: refused - the closure's env takes the by-value parameter over, so f consumes x and main's read is a use after a move (main 3358873a: accepted, heap-use-after-free). A capture only read could be a borrow instead: a precision follow-up.
// map: §7.6 | A2 | rejected | - | agora #868 adversarial neighbour: a closure that only reads the captured parameter
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop ` ( string_data . b s ) ) ) } }

@ mk s t → R { ^ @ R { ( string_from t ) 1 } }

@ exec ( @ v ) g → v { ( g ) }

@ f ( Vec R ) log R p → i { ( exec \ → v { ( nurl_println ( string_data . p s ) ) } ) ^ 1 }

@ main → i {
    : ~ ( Vec R ) log ( vec_new [R] )
    : R x ( mk `a value long enough for the heap buffer, surely, yes` )
    : i b ( f log x )
    ( nurl_println ( string_data . x s ) )
    ^ 0
}
