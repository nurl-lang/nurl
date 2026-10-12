// A RawBlock (stdlib/core/mem.nu) is raw memory that releases itself: code
// works through a typed pointer into it and frees nothing by hand. Moved
// into a struct, it goes with the struct (the sanitizer run checks that
// nothing leaks and nothing is freed twice).
$ `stdlib/core/mem.nu`

: Table { RawBlock mem * i cells i n }

unsafe @ table_new i n → Table {
    : RawBlock mem ( raw_block * n 8 )
    : *i cells # *i ( raw_block_ptr mem )
    : ~ i k 0
    ~ < k n { = . cells k * k k = k + k 1 }
    ^ @ Table { mem cells n }
}

unsafe @ main → i {
    : RawBlock xb ( raw_block * 4 8 )
    : *f x # *f ( raw_block_ptr xb )
    = . x 0 1.5 = . x 1 2.5 = . x 2 3.0 = . x 3 4.0
    ( nurl_println_int # i + + + . x 0 . x 1 . x 2 . x 3 )
    : Table t ( table_new 10 )
    : *i c . t cells
    ( nurl_println_int . c 9 )
    ( nurl_println_int . t n )
    ^ 0
}
