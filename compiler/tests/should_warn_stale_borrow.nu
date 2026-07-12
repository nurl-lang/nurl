// A pointer borrowed from a container (vec_data/string_data/bytes_data)
// dangles once the container is grown — the buffer may be reallocated
// under it. The mutation here is inside a loop body, the use after it.
// Re-fetching the pointer clears the diagnostic (the second read below
// is silent), which is exactly the fix the note suggests.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : ( Vec u ) v ( vec_with_cap [u] 4 )
    ( vec_push [u] v # u 7 )
    : ~ * u p ( vec_data [u] v )
    : ~ i k 0
    ~ < k 100 {
        ( vec_push [u] v # u 1 )  // grows → realloc → p dangles
        = k + k 1
    }
    : i stale # i . p 0  // warns: 'p' is stale
    = p ( vec_data [u] v )  // re-fetch
    : i fresh # i . p 0  // silent
    ( nurl_print ( nurl_str_int + - stale stale fresh ) ) ( nurl_print `\n` )
    ( vec_free [u] v )
    ^ 0
}
