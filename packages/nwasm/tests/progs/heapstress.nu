// Six threads hammering the guest allocator with mixed sizes and
// strings — the same allocator paths the relay's framing uses.
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : Mutex m ( mutex_new )
    : *i total ( nurl_alloc 8 )
    ( nurl_poke # s total 0 0 )
    : ( @ v ) body \ → v {
        : ~ i sum 0
        : ~ i r 0
        ~ < r 8 {
            : ( Vec String ) strs ( vec_new [String] )
            : ~ i k 0
            ~ < k 60 {
                : String s ( string_from `frame-` )
                ( string_push_int s + k r )
                ( string_push_str s `-payload-payload-payload` )
                ( vec_push [String] strs s )
                = sum + sum ( string_len s )
                = k + k 1
            }
            : ( Vec u ) buf ( vec_with_cap [u] 5 )
            : ~ i b 0
            ~ < b 400 { ( vec_push [u] buf # u & b 255 ) = b + b 1 }
            ( vec_free [u] buf )
            ( vec_free_with [String] strs \ String s → v { ( string_free s ) } )
            = r + r 1
        }
        ( mutex_lock m )
        ( nurl_poke # s total 0 + ( nurl_peek # s total 0 ) sum )
        ( mutex_unlock m )
    }
    : ( Vec s ) ths ( vec_new [s] )
    : ~ i i 0
    ~ < i 4 { ?? ( thread_spawn body ) { T t → { ( vec_push [s] ths . t raw ) } F e → { ( nurl_println `spawn failed` ) } } = i + i 1 }
    : i n ( vec_len [s] ths )
    : ~ i j 0
    ~ < j n { ?? ( vec_get [s] ths j ) { T r → ( thread_join @ Thread { r } ) F → {} } = j + j 1 }
    ( nurl_print `threads=` ) ( nurl_print ( nurl_str_int n ) )
    ( nurl_print ` total=` ) ( nurl_println ( nurl_str_int ( nurl_peek # s total 0 ) ) )
    ( vec_free [s] ths ) ( nurl_free # s total ) ( mutex_free m )
    ^ 0
}
