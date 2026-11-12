// A generic struct may be declared anywhere in the program (agora #716):
// every template is collected before the first instance is made, so an
// instance named above its template — in a binding, a parameter, an impl
// header, a plain struct's field, another template's field — has its fields
// there, and what it owns is released with it.
$ `stdlib/core/vec.nu`
$ `stdlib/core/string.nu`

% Size { @ size Self s → i }

% Size ( Bag i ) {
    @ size ( Bag i ) s → i { ^ + ( vec_len [i] . s items ) . s extra }
}

: Shelf { ( Bag String ) books i floor }

@ total ( Bag String ) b → i { ^ + ( vec_len [String] . b items ) . b extra }

@ deep ( Outer i ) o → i { ^ + . . o inner x . o n }

@ main → i {
    : ( W i ) w @ ( W i ) { 5 }
    ( nurl_println_int . w x )
    : ~ ( Vec String ) v ( vec_new [String] )
    ( vec_push [String] v ( string_from `a long enough string to be on the heap` ) )
    ( vec_push [String] v ( string_from `b` ) )
    : ( Bag String ) b @ ( Bag String ) { v 3 }
    ( nurl_println_int ( total b ) )
    : ~ ( Vec i ) vi ( vec_new [i] )
    ( vec_push [i] vi 4 )
    : ( Bag i ) bi @ ( Bag i ) { vi 6 }
    ( nurl_println_int ( size bi ) )
    : ( Outer i ) o @ ( Outer i ) { @ ( Inner i ) { 40 } 2 }
    ( nurl_println_int ( deep o ) )
    : ~ ( Vec String ) v2 ( vec_new [String] )
    ( vec_push [String] v2 ( string_from `another string that lives on the heap` ) )
    : Shelf s @ Shelf { @ ( Bag String ) { v2 10 } 9 }
    ( nurl_println_int + ( total . s books ) . s floor )
    ^ 0
}

: W [T] { T x }

: Bag [T] { ( Vec T ) items i extra }

: Outer [T] { ( Inner T ) inner i n }

: Inner [T] { T x }
