// cursor_given_a_field_in_one_arm_then_handed_back_runs_clean: the field store through `: ~ P e p` is inside one arm of a `?`, then `^ e`; both paths run.
// Closed (agora #781): the field-owner flag is the run-time answer — set on the path that stored, clear on the other, where e hands p's value back whole.
// main 820aafb4: heap-use-after-free on the path that stores.
// map: §7.6 | A2 | runs-clean | - | agora #781: a cursor given a field in one arm then handed back
$ `stdlib/core/string.nu`

: P { String name i n }
: Q { String a String b }

@ one i c → P { : ~ P p @ P { ( string_from `orig, a name long enough for a heap buffer` ) c } : ~ P e p ? == c 1 { = . e name ( string_from `replaced, a name long enough for a heap buffer` ) } {} ^ e }

@ two i c → Q { : ~ Q p @ Q { ( string_from `a, a name long enough for a heap buffer` ) ( string_from `b, a name long enough for a heap buffer` ) } : ~ Q e p ? == c 1 { = . e b ( string_from `new b, a name long enough for a heap buffer` ) } {} ^ e }

@ main → i {
    : P r ( one 1 ) ( nurl_println ( string_data . r name ) )
    : P r2 ( one 0 ) ( nurl_println ( string_data . r2 name ) )
    : Q q ( two 1 ) ( nurl_println ( string_data . q b ) )
    : Q q2 ( two 0 ) ( nurl_println ( string_data . q2 b ) )
    ^ 0
}
