// inout_option_parameter_given_a_call_that_may_lend_itself_or_another_argument: agora #412 — `= o ( pick o other k )` with `o` an `inout` option parameter: the caller's binding is given back what the call may lend
// Closed: an `inout` parameter is refused as a local owner is (agora #412).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #412: `= o ( pick o other k )` with `o` an `inout` option parameter: the caller's binding is given back what the call may lend
$ `stdlib/core/string.nu`

@ pick ? String a ? String b i k → ?String { ? == k 0 { ^ a } { ^ b } }

@ mk s t → ?String { ^ @ ?String { T ( string_from t ) } }

@ show ? String o → v { ?? o { T s → { ( nurl_println ( string_data s ) ) } F → { ( nurl_println `none` ) } } }

@ upd inout ? String o ? String other i k → v { = o ( pick o other k ) }

@ run i k → v {
    : ?String other ( mk `another value long enough for the heap` )
    : ~ ? String o ( mk `a value long enough for the heap here` )
    ( upd o other k )
    ( show o )
    ( show other )
}

@ main → i {
    ( run 0 )
    ( run 1 )
    ^ 0
}
