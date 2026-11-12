// noncopyable_enum_replaced_above_its_declaration_is_dropped_runs_clean: as noncopyable_enum_bound_above_its_declaration_is_dropped_runs_clean, the binding given a new value (`= e ( mke 5 )`): neither value was dropped
// Closed: as that probe (agora #752).
// main 3c4322c: LeakSanitizer: detected memory leaks.
// map: §7.6 | A2 | runs-clean | - | agora #752: a non-copyable enum replaced above its declaration: neither value dropped
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ f1 i k → i { : ~ E e ( mke k ) = e ( mke 5 ) ^ 1 }

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop R ` ( string_data . b s ) ) ) } }

: | E { EA R EB i }

@ mke i k → E { ? > k 0 { ^ @ E { EA @ R { ( string_from `a payload string long enough for the heap` ) k } } } {} ^ @ E { EB k } }

@ main → i { ( nurl_println_int ( f1 3 ) ) ^ 0 }
