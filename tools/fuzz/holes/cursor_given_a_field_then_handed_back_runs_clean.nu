// cursor_given_a_field_then_handed_back_runs_clean: `: ~ P e p`, then `= . e name …`, then `^ e` — for a struct of one String and of two.
// Closed (agora #781): the cursor's own fields go out with it where the rest moves out uncopied, the values they replaced are the owner's to drop, and the owner's flag clears whatever its first buffer says.
// main 820aafb4: heap-use-after-free (the new name freed at the return, the second field freed by the owner).
// map: §7.6 | A2 | runs-clean | - | agora #781: a cursor given a field then handed back
$ `stdlib/core/string.nu`

: P { String name i n }
: Q { String a String b }

@ one i n → P { : ~ P p @ P { ( string_from `orig, a name long enough for a heap buffer` ) n } : ~ P e p = . e name ( string_from `replaced, a name long enough for a heap buffer` ) ^ e }

@ two → Q { : ~ Q p @ Q { ( string_from `orig a, a name long enough for a heap buffer` ) ( string_from `orig b, a name long enough for a heap buffer` ) } : ~ Q e p = . e a ( string_from `replaced a, long enough for a heap buffer` ) ^ e }

@ main → i {
    : P r ( one 3 ) ( nurl_println ( string_data . r name ) )
    : Q q ( two ) ( nurl_println ( string_data . q a ) ) ( nurl_println ( string_data . q b ) )
    ^ 0
}
