// inout_drop_struct_taken_on_some_paths_is_dropped_on_the_others.nu — a
// function that hands its `inout` parameter of a `% Drop` type to a `sink`
// on some paths only (Agora #849, #776's rest).
//
// Such a function is summarised as consuming the parameter, so its caller
// drops nothing: it owns the caller's value then, and drops it on the way
// out wherever it did not hand it on, as a `sink` parameter is dropped.
// Before, on every path that took nothing the caller's value leaked (its
// destructor never ran). A `= p` drops the old value only while the slot
// still holds one: not after the value was taken. Each value below is
// dropped exactly once; the destructor prints its number.

$ `stdlib/std/panic.nu`
$ `stdlib/core/string.nu`

: D { String name i n }

% Drop ( D ) { @ drop D d → v { ( nurl_println_int . d n ) } }

@ mk i k → D { ^ @ D { ( string_from `a name long enough to own a heap buffer` ) k } }

@ eat sink D d → i { ^ . d n }

// Handed on in one arm of a statement `?`.
@ g3 inout D p i c → i {
    ? == c 1 { ^ ( eat p ) } {}
    ^ 0
}

// Through another function's `inout`.
@ g4 inout D p i c → i { ^ ( g3 p c ) }

// Given a new value first (the old one dropped), then handed on in one arm.
@ g5 inout D p i c → i {
    = p ( mk + 30 c )
    ? == c 1 { ^ ( eat p ) } {}
    ^ 0
}

// Taken in one arm, then given a new value on every path: the `=` drops
// nothing where the value was taken.
@ g6 inout D p i c → i {
    ? == c 1 { ( eat p ) } {}
    = p ( mk + 60 c )
    ^ 0
}

// An early return before the take.
@ g7 inout D p i c → i {
    ? == c 0 { ^ 7 } {}
    ^ ( eat p )
}

// In a loop: a new value each round, taken in the last round on one run.
@ g8 inout D p i c → i {
    : ~ i k 0
    ~ < k 3 {
        = p ( mk + 80 k )
        ? & == c 1 == k 2 { ^ ( eat p ) } {}
        = k + k 1
    }
    ^ 0
}

// A field replaced, then handed on in one arm.
@ gf inout D p i c → i {
    = . p name ( string_from `a new name long enough to own a heap buffer` )
    ? == c 1 { ^ ( eat p ) } {}
    = . p n + . p n 100
    ^ 0
}

// A panic before the take: the value is dropped once, by the unwind.
@ gp inout D p i c → i {
    ? == c 1 { ^ ( eat p ) } {}
    ? == c 0 { ( panic `boom` ) } {}
    ^ 0
}

// A function that never hands it on: the caller's value stays the caller's.
@ keep inout D p i c → i {
    = p ( mk + 20 c )
    ^ 0
}

@ run i c → v {
    : ~ D w3 ( mk + 10 c )
    ( nurl_println_int ( g3 w3 c ) )
    : ~ D w4 ( mk + 40 c )
    ( nurl_println_int ( g4 w4 c ) )
    : ~ D w5 ( mk + 50 c )
    ( nurl_println_int ( keep w5 c ) )
    ( nurl_println_int ( g5 w5 c ) )
    : ~ D w6 ( mk + 150 c )
    ( nurl_println_int ( g6 w6 c ) )
    : ~ D w7 ( mk + 70 c )
    ( nurl_println_int ( g7 w7 c ) )
    : ~ D w8 ( mk + 90 c )
    ( nurl_println_int ( g8 w8 c ) )
    : ~ D wf ( mk + 110 c )
    ( nurl_println_int ( gf wf c ) )
    : !v PanicInfo r ( recover \ → v {
        : ~ D wp ( mk + 170 c )
        ( nurl_println_int ( gp wp c ) )
    } )
    ( nurl_println `--` )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ( run 2 )
    ^ 0
}
