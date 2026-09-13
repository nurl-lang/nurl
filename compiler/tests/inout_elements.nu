$ `stdlib/core/vec.nu`

: Cell { i value i calls }

@ bump inout i n → v { = n + n 1 }

@ update inout Cell cell → v { = . cell value + . cell value 10 = . cell calls + . cell calls 1 }

@ forward [T] inout T value → v { ( concrete [T] value ) }

@ concrete [T] inout T value → v { = . value calls + . value calls 2 }

@ position inout i n → i { = n + n 1 ^ - n 1 }

@ main → i {
    : ( Vec Cell ) cells ( vec_new [Cell] )
    ( vec_push [Cell] cells @ Cell { 1 0 } )
    ( vec_push [Cell] cells @ Cell { 2 0 } )
    : ~ * Cell data ( vec_data [Cell] cells )
    : ~ i counter 0
    ( update . data ( position counter ) )
    ( forward [Cell] . data ( position counter ) )
    // A named field through the same pointer writes into the first element.
    ( bump . data value )
    : Cell first . data 0
    : Cell second . data 1
    ( nurl_println_int . first value )
    ( nurl_println_int . first calls )
    ( nurl_println_int . second value )
    ( nurl_println_int . second calls )
    ( nurl_println_int counter )
    ( vec_free [Cell] cells )
    : ( Vec i ) ints ( vec_new [i] )
    ( vec_push [i] ints 7 )
    : ~ * i numbers ( vec_data [i] ints )
    ( bump . numbers # i32 0 )
    ( nurl_println_int . numbers 0 )
    ( vec_free [i] ints )
    ^ 0
}
