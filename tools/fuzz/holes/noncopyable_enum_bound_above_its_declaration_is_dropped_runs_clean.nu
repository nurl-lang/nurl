// noncopyable_enum_bound_above_its_declaration_is_dropped_runs_clean: an enum whose payload has a `% Drop` (and cannot be copied) bound in a function above its declaration: its compiler drop was registered only at gen_enum_decl, so e was never dropped
// Closed: read_type_layouts registers the drop impl (`drop##%E`) beside `autodrop##%E` for every enum with a compiler drop; gen_enum_decl still emits it (`autodroppre##`, agora #752). Each `drop R` line is printed once.
// main 3c4322c: LeakSanitizer: detected memory leaks (no `drop R` line).
// map: §7.6 | A2 | runs-clean | - | agora #752: a non-copyable enum bound above its declaration was never dropped
$ `stdlib/core/string.nu`

@ f1 i k → i { : E e ( mke k ) ^ ?? e { EA r → 7 EB j → j } }

: R { String s i n }

% Drop R { @ drop R b → v { ( nurl_println ( nurl_str_cat `drop R ` ( string_data . b s ) ) ) } }

: | E { EA R EB i }

@ mke i k → E { ? > k 0 { ^ @ E { EA @ R { ( string_from `a payload string long enough for the heap` ) k } } } {} ^ @ E { EB k } }

@ main → i { ( nurl_println_int ( f1 3 ) ) ( nurl_println_int ( f1 0 ) ) ^ 0 }
