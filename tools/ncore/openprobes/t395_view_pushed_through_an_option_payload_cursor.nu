// map: §2.13 | A2 | rejected | - | agora #395: a view pushed through `?? ov { T w → ( vec_push w … ) }`, an option payload cursor, read after its source's block
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : ? ( Vec s ) ov @ ?( Vec s ) { T ( vec_new [s] ) }
    {
        : String loc ( string_from `a heap string freed at the end of this block, long enough for the heap` )
        ?? ov { T w → ( vec_push [s] w ( string_data loc ) ) F → {} }
    }
    ?? ov { T w → ( nurl_println ( vec_at [s] w 0 ) ) F → {} }
    ^ 0
}
