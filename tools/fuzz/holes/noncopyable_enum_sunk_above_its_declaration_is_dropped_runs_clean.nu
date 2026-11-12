// noncopyable_enum_sunk_above_its_declaration_is_dropped_runs_clean: as noncopyable_enum_bound_above_its_declaration_is_dropped_runs_clean, handed to a `sink` parameter above the declaration
// Closed: as that probe (agora #752).
// main 3c4322c: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #752: a non-copyable enum handed to a `sink` above its declaration was never dropped
$ `stdlib/core/string.nu`

@ eat sink E e → i { ^ ?? e { EA r → 7 EB j → j } }

@ f1 i k → i { : E e ( mke k ) ^ ( eat e ) }

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop R ` ( string_data . b s ) ) ) } }

: | E { EA R EB i }

@ mke i k → E { ? > k 0 { ^ @ E { EA @ R { ( string_from `a payload string long enough for the heap` ) k } } } {} ^ @ E { EB k } }

@ main → i { ( nurl_println_int ( f1 3 ) ) ( nurl_println_int ( f1 0 ) ) ^ 0 }
