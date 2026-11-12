// generic_struct_declared_below_its_first_use_read_and_released_runs_clean: generic structs declared at the end of the file — one of them a field of another — are named above in a binding, a parameter, an impl header and a plain struct's field; their fields are read there and the `Vec`s of `String`s they own go with them.
// main: refused — "type '( Bag i )' has no field 'items'": a template was learned by the same walk that makes the instances, so an instance named above it had no fields.
// map: §6.5 | A3 | runs-clean | - | guard: generic struct instances named above their templates, read and dropped: a generic struct may be declared anywhere (agora #716)
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

% Size { @ size Self s → i }

% Size ( Bag i ) {
    @ size ( Bag i ) s → i { ^ + ( vec_len [i] . s items ) . s extra }
}

: Shelf { ( Bag String ) books i floor }

@ total ( Bag String ) b → i { ^ + ( vec_len [String] . b items ) . b extra }

@ deep ( Outer String ) o → i { ^ + ( vec_len [String] . . o inner items ) . o n }

@ main → i {
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a long enough string to be on the heap` ) )
    ( vec_push [String] v ( string_from `b` ) )
    : ( Bag String ) b @ ( Bag String ) { v 3 }
    : ~ ( Vec i ) vi ( vec_new [i] )
    ( vec_push [i] vi 4 )
    : ( Bag i ) bi @ ( Bag i ) { vi 6 }
    : ~ ( Vec String ) v2 ( vec_new [String] )
    ( vec_push [String] v2 ( string_from `another string that lives on the heap` ) )
    : Shelf s @ Shelf { @ ( Bag String ) { v2 10 } 9 }
    : ~ ( Vec String ) v3 ( vec_new [String] )
    ( vec_push [String] v3 ( string_from `a third string that lives on the heap` ) )
    : ( Outer String ) o @ ( Outer String ) { @ ( Bag String ) { v3 0 } 2 }
    ^ - + + + ( total b ) ( size bi ) + ( total . s books ) . s floor ( deep o ) 35
}

: Outer [T] { ( Bag T ) inner i n }

: Bag [T] { ( Vec T ) items i extra }
