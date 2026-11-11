// aliased_and_underscore_named_structs_own_and_drop_their_fields_runs_clean: the guard of the base rule — a struct named `__Bag` and a module's `Point`-holder behind an alias are ordinary types of the program: built, copied with `mem_dup`, kept in a `Vec`, sent to a thread (their fields are Send) and dropped, every buffer freed once.
// map: §6.5 | A3 | runs-clean | - | guard: a struct named `__Bag` and one behind an import alias own, copy, cross a thread and drop as any struct does — their base is their whole declared name (agora #639)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`
$ `stdlib/std/thread.nu`
$ `compiler/tests/alias_rewrite_types_mod.nu` geo

: __Bag { ( Vec String ) names i n }

: Shape { geo::Point at __Bag bag }

@ fill __Bag b i n → v {
    : ~ i k 0
    ~ < k n {
        ( vec_push [String] . b names ( string_from `a name long enough to live on the heap, not inline` ) )
        = k + k 1
    }
}

@ main → i {
    : __Bag b @ __Bag { ( vec_new [String] ) 0 }
    ( fill b 4 )
    : __Bag c ( mem_dup b )
    ( fill c 2 )
    : ( Vec __Bag ) all ( vec_new [__Bag] )
    ( vec_push [__Bag] all c )
    : Shape sh @ Shape { ( geo::make_point 3 4 ) ( mem_dup b ) }
    : ~ i got 0
    ?? ( thread_spawn \ → v { ( fill . sh bag 3 ) } ) {
        T t → { ( thread_join t ) = got 1 }
        F _ → {}
    }
    ^ - + + ( vec_len [String] . b names ) ( vec_len [String] . ( vec_at [__Bag] all 0 ) names ) got 11
}
