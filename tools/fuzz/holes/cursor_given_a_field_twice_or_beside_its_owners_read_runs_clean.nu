// cursor_given_a_field_twice_or_beside_its_owners_read_runs_clean: a field stored twice through `: ~ P e p`, and one stored with the owner's field read after; each then `^ e`.
// Closed (agora #781): the first store keeps the owner's value of the field, the second drops the cursor's own, and the owner reads its own value.
// main 820aafb4: heap-use-after-free at the return.
// map: §7.6 | A2 | runs-clean | - | agora #781: a cursor given a field twice, or beside its owner's read
$ `stdlib/core/string.nu`

: P { String name i n }

@ twice → P { : ~ P p @ P { ( string_from `orig, a name long enough for a heap buffer` ) 1 } : ~ P e p = . e name ( string_from `first, a name long enough for a heap buffer` ) = . e name ( string_from `second, a name long enough for a heap buffer` ) ^ e }

@ beside → P { : ~ P p @ P { ( string_from `orig, a name long enough for a heap buffer` ) 1 } : ~ P e p = . e name ( string_from `field, a name long enough for a heap buffer` ) ( nurl_println ( string_data . p name ) ) ^ e }

@ main → i {
    : P r ( twice ) ( nurl_println ( string_data . r name ) )
    : P r2 ( beside ) ( nurl_println ( string_data . r2 name ) )
    ^ 0
}
