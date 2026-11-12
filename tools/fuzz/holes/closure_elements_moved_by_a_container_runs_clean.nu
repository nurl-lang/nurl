// closure_elements_moved_by_a_container_runs_clean: closures as a HashMap's values across two growths, and as a Vec's elements through vec_swap, vec_reverse, vec_retain and sort_by; each is called afterwards.
// Guard for agora #706: a container that moves its elements moves closures too — a rehash stores slot to slot, and an element that changes places goes back into the buffer as it is (mem_put_back, which a closure element store honours). Before, the element was read into a binding and the binding stored: for a closure that is a copy, so the slot got a clone of its environment and the one it came with was never released.
// main 0dcd56f: accepted, LeakSanitizer: one closure environment per element the growth rehashed, and per element swapped, reversed, retained or sorted.
// map: §7.5 | A2 | runs-clean | - | agora #706 guard: closures moved by a HashMap's growth and by vec_swap / vec_reverse / vec_retain / sort_by keep one environment each, released once
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/hashmap.nu`
$ `stdlib/std/sort.nu`

@ mk i n → ( Vec ( @ i ) ) {
    : ~ ( Vec ( @ i ) ) v ( vec_new [( @ i )] )
    : ~ i k 0
    ~ < k n {
        : i kk % * k 7919 n
        ( vec_push [( @ i )] v \ → i { ^ kk } )
        = k + k 1
    }
    ^ v
}

@ main → i {
    : ( HashMap i ( @ i ) ) m ( map_new [i ( @ i )] )
    : ~ i k 0
    ~ < k 20 {
        : i kk k
        : ?( @ i ) _p ( map_set [i ( @ i )] m k \ → i { ^ + kk 1 } \ i x → i { ^ ( hash_int x ) } \ i x i y → b { ^ == x y } )
        = k + k 1
    }
    : ~ i sum 0
    ( map_each [i ( @ i )] m \ i key ( @ i ) f → v { = sum + sum ( f ) } )
    : ~ ( Vec ( @ i ) ) a ( mk 60 )
    : b _s ( vec_swap [( @ i )] a 0 59 )
    ( vec_reverse [( @ i )] a )
    ( vec_retain [( @ i )] a \ ( @ i ) f → b { ^ == % ( f ) 2 0 } )
    ( sort_by [( @ i )] a \ ( @ i ) x ( @ i ) y → i { ^ - ( x ) ( y ) } )
    ~ f a { = sum + sum ( f ) }
    ( nurl_println ( nurl_str_int sum ) )
    ^ 0
}
