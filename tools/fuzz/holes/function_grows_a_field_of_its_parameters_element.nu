// function_grows_a_field_of_its_parameters_element: agora #461 — `grow` grows `. ( vec_at hs 0 ) data` of its parameter; the caller keeps a slice of it across `( grow hs )`
// Closed: a function's drop and irealloc summaries follow a lend its names miss, by edges conditioned on the source expression and decided at module end (agora #461).
// main cd8c0a6: accepted; AddressSanitizer: heap-use-after-free.
// map: §2.10 | A2 | rejected | - | agora #461: a function grows a field of its parameter's element
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`

: R { ( Vec u ) data }

@ grow ( Vec R ) hs → v {
    ( vec_reserve [u] . ( vec_at [R] hs 0 ) data 4096 )
}

@ main → i {
    : ( Vec R ) hs ( vec_new [R] )
    ( vec_push [R] hs @ R { ( vec_new [u] ) } )
    ( vec_push [u] . ( vec_at [R] hs 0 ) data 7 )
    : ( Slice u ) sl ( slice_from_vec [u] . ( vec_at [R] hs 0 ) data )
    ( grow hs )
    ( nurl_println_int # i ( slice_at [u] sl 0 ) )
    ^ 0
}
