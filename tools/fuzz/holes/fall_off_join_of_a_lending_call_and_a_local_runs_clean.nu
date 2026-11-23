// fall_off_join_of_a_lending_call_and_a_local_runs_clean: AGORA-866 — `? c ( id x ) l` as the body's fall-off value, `id` lending its `% Drop` argument back: the call's lend is the caller's, the local moves out, as for `^`
// map: §7.6 | A2 | runs-clean | - | `? c ( id x ) l` as the body's fall-off value, `id` lending its `% Drop` argument back: the call's lend is the caller's, the local moves out, as for `^`
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → D { ^ @ D { ( string_from `a string long enough for a heap buffer ok` ) } }

@ id D d → D { ^ d }

@ g D x b c → D { : D l ( mk ) ? c ( id x ) l }

@ main → i { : D x ( mk ) : D r ( g x T ) : D q ( g x F ) ( nurl_println_int + + ( string_len . r s ) ( string_len . q s ) ( string_len . x s ) ) ^ 0 }
