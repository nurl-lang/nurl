// Forward and mutually recursive inout calls use the declared address ABI.
: Counter { i n i max }

@ main → i {
    : ~ Counter c @ Counter { 0 10 }
    ( bump c )
    ( check_counter c 1 )
    ( odd c 5 )
    ( check_counter c 6 )
    : ~ i count 10
    ( mixed 9 count 1 c )
    ( check_counter c 7 )
    ? != count 20 { ^ 2 } {}
    ( nurl_print `forward inout: ok\n` )
    ^ 0
}

@ check_counter Counter c i expected → v {
    ? != . c n expected { ( nurl_exit 1 ) } {}
}

@ bump inout Counter c → v { = . c n + . c n 1 }

@ odd inout Counter c i left → v {
    ? <= left 0 { ^ } {}
    ( bump c )
    ( even c - left 1 )
}

@ even inout Counter c i left → v {
    ? <= left 0 { ^ } {}
    ( bump c )
    ( odd c - left 1 )
}

@ mixed i a inout i n i b inout Counter c → v {
    = n + n + a b
    ( bump c )
}
