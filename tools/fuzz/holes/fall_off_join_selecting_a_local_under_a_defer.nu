// fall_off_join_selecting_a_local_under_a_defer: AGORA-866 — `? c x l` as the body's fall-off value under a `;` defer: the defer runs after the value is the caller's, so the local is not moved out and its lend would need a copy, refused as for `^ ? c x l`
// map: §7.6 | A2 | rejected | - | `? c x l` as the body's fall-off value under a `;` defer: the defer runs after the value is the caller's, so the local is not moved out and its lend would need a copy, refused as for `^ ? c x l`
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → D { ^ @ D { ( string_from `a string long enough for a heap buffer ok` ) } }

@ g D x b c → D { : D l ( mk ) ; { ( nurl_println `deferred` ) } ? c x l }

@ main → i { : D x ( mk ) : D r ( g x T ) : D q ( g x F ) ( nurl_println_int + ( string_len . r s ) ( string_len . q s ) ) ^ 0 }
