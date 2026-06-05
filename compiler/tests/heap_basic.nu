// Regression: std/heap.nu binary heap. Min-heap via `a - b`: pushing a
// scrambled set and popping must yield ascending order; peek must show
// the current minimum. Returns the failure count.

$ `stdlib/std/heap.nu`

@ main → i {
    : ~ i fails 0

    : ( Heap i ) h ( heap_new [i] )
    ( heap_push [i] h 5 \ i a i b → i { ^ - a b } )
    ( heap_push [i] h 3 \ i a i b → i { ^ - a b } )
    ( heap_push [i] h 8 \ i a i b → i { ^ - a b } )
    ( heap_push [i] h 1 \ i a i b → i { ^ - a b } )
    ( heap_push [i] h 9 \ i a i b → i { ^ - a b } )
    ( heap_push [i] h 2 \ i a i b → i { ^ - a b } )

    ? != ( heap_len [i] h ) 6 { ( nurl_print `  FAIL len\n` ) = fails + fails 1 } {}
    ?? ( heap_peek [i] h ) { T v → { ? != v 1 { ( nurl_print `  FAIL peek\n` ) = fails + fails 1 } {} } F → { ( nurl_print `  FAIL peek none\n` ) = fails + fails 1 } }

    // Pop everything — must come out 1,2,3,5,8,9.
    : ~ i prev -1
    : ~ b ordered T
    : ~ i seen 0
    : ~ b go T
    ~ go {
        ?? ( heap_pop [i] h \ i a i b → i { ^ - a b } ) {
            T v → {
                ? < v prev { = ordered F } {}
                = prev v
                = seen + seen 1
            }
            F → { = go F }
        }
    }
    ? ! ordered { ( nurl_print `  FAIL not ascending\n` ) = fails + fails 1 } {}
    ? != seen 6 { ( nurl_print `  FAIL popped count\n` ) = fails + fails 1 } {}
    ? != prev 9 { ( nurl_print `  FAIL last != max\n` ) = fails + fails 1 } {}
    ? ! ( heap_is_empty [i] h ) { ( nurl_print `  FAIL not empty\n` ) = fails + fails 1 } {}
    ( heap_free [i] h )

    ? == fails 0 { ( nurl_print `heap: all checks PASS\n` ) } {
        ( nurl_print `heap: ` ) ( nurl_print ( nurl_str_int fails ) ) ( nurl_print ` FAILURES\n` )
    }
    ^ fails
}
