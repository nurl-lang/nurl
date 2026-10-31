// join_initialised_string_cursor_leaks: a mutable string binding declared from a `?` join whose arms own nothing (`: ~ s r ? c a b`, views or literals), then advanced like a cursor (`= r ( rest_of r )`), had no owner slot: every fresh string assigned to it was released by no one.
// Closed: such a binding gets the empty owner slot a cursor declared from an identifier or a call already had, so each assignment frees what the binding owned before and the last value goes at scope end (mem_cursor_owner_slot).
// main (before this PR): LeakSanitizer, one string per step.
// map: §7.1 | A2 | runs-clean | h203 | string cursor from ?-join has no owner slot: each assigned fresh string leaks
$ `stdlib/core/string.nu`

@ rest_of s w → s {
    : i k ( nurl_str_find w ` ` )
    ? < k 0 { ^ ( nurl_str_cat `` `` ) } {}
    ^ ( nurl_str_slice w + k 1 - - ( nurl_str_len w ) k 1 )
}

@ count_words s a s b → i {
    : ~ s r ? > ( nurl_str_len a ) 0 a b
    : ~ i n 0
    ~ != 0 ( nurl_str_len r ) {
        = r ( rest_of r )
        = n + n 1
    }
    ^ n
}

@ main → i {
    : s words ( nurl_str_cat `the words of a sentence, ` `long enough for the heap` )
    ( nurl_println_int ( count_words words `` ) )
    ^ 0
}
