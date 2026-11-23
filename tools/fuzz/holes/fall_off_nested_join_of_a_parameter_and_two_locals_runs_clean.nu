// fall_off_nested_join_of_a_parameter_and_two_locals_runs_clean: AGORA-866 — a nested `? c ? d x l m` as the body's fall-off value, `x` a `% Drop` parameter and `l`, `m` locals: each selected local moves out on its path, as for `^`
// map: §7.6 | A2 | runs-clean | - | a nested `? c ? d x l m` as the body's fall-off value, `x` a `% Drop` parameter and `l`, `m` locals: each selected local moves out on its path, as for `^`
$ `stdlib/core/string.nu`

: D { String s }

% Drop D { @ drop D d → v { ( nurl_println `drop` ) } }

@ mk → D { ^ @ D { ( string_from `a string long enough for a heap buffer ok` ) } }

@ g D x b c b d → D { : D l ( mk ) : D m ( mk ) ? c ? d x l m }

@ main → i { : D x ( mk ) : D r ( g x T F ) : D q ( g x F T ) : D w ( g x T T ) ( nurl_println_int + + ( string_len . r s ) ( string_len . q s ) ( string_len . w s ) ) ^ 0 }
