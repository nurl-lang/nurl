// literal_nested_moved_twice: a struct literal moving a binding into one field and into a literal nested in another — `^ @ Two { t @ Holder { t } }` — made two owners of one value: the nested literal's move reached neither the borrow walk (it runs after the statement) nor the outer literal's field check (h205), which saw only bare names and calls.
// Closed: a literal nested in another hands the names it moved in bare up to it (g_lm_inner), and the outer literal checks them as moves of the field holding the nested one (bck_check_lit_moves).
// main (before this PR): heap-use-after-free, releasing the String the second owner already released.
// map: §2.12 | A2 | rejected | h206 | struct literal moves t into a field and into a nested literal: two owners
$ `stdlib/core/string.nu`

: Holder { String h }
: Two { String a Holder b }

@ mk → Two {
    : String t ( string_from `seven` )
    ^ @ Two { t @ Holder { t } }
}

@ main → i {
    : Two w ( mk )
    ( nurl_print ( string_data . w a ) )
    ( nurl_print `\n` )
    ^ 0
}
