// Locked [T]: the one way safe code shares state that threads change.
// An Arc's payload is frozen once made (docs/MEMORY.md §6.5), so a
// Vec eight workers append to, a String they all log into and a counter
// the main thread updates afterwards each live in a Locked, and every
// change happens inside locked_with / locked_set — which hold that
// Locked's own mutex, so the lock that guards the data is the one the
// type names. No lost update: 8 × 2000 pushes give 16000 elements.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`

@ main → i {
    : ( Locked ( Vec i ) ) xs ( locked_new [( Vec i )] ( vec_new [i] ) )
    : ( Locked i ) count ( locked_new [i] 0 )
    : ( Locked String ) log ( locked_new [String] ( string_from `` ) )
    : ( Vec Thread ) ts ( vec_new [Thread] )
    : ~ i j 0
    ~ < j 8 {
        : !Thread ThreadErr r ( thread_spawn \ → v {
            : ~ i k 0
            ~ < k 2000 {
                ( locked_with [( Vec i )] xs \ ( Vec i ) v → v { ( vec_push [i] v k ) } )
                ( locked_with [String] log \ String s → v { ( string_push_char s 46 ) } )
                = k + k 1
            }
        } )
        ?? r { T t → { ( vec_push [Thread] ts t ) } F e → {} }
        = j + j 1
    }
    = j 0
    ~ < j ( vec_len [Thread] ts ) { ?? ( vec_get [Thread] ts j ) { T t → { ( thread_join t ) } F _ → {} } = j + j 1 }
    ( locked_set [i] count 41 )
    ( locked_set [i] count + ( locked_get [i] count ) 1 )
    : ( Vec i ) snap ( locked_get [( Vec i )] xs )
    : String l ( locked_get [String] log )
    ( nurl_print `len=` ) ( nurl_println_int ( vec_len [i] snap ) )
    ( nurl_print `log=` ) ( nurl_println_int ( string_len l ) )
    ( nurl_print `count=` ) ( nurl_println_int ( locked_get [i] count ) )
    ^ 0
}
