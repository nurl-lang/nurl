// packages/bench/src/report.nu — throughput derivation + table formatting
// on top of the standard library's std/bench harness.
//
// std/bench measures ns/op and allocations/op. `bench_thpt` runs a body
// through it and derives a throughput figure: given `units_per_op` (bytes,
// elements, or floating-point ops processed in one call) the rate is
//
//     units_per_op * 1000 / ns_per_op
//
// which is MB/s when the unit is bytes, million-elements/s when it is
// elements, and MFLOP/s when it is flops — one formula, because a unit per
// nanosecond is a million units per millisecond is a billion per second.

$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/bench.nu`

: BenchRow {
    String name
    i ns_per_op
    i allocs_per_op
    i thpt
    String unit
}

@ bench_row_free BenchRow r → v {
    ( string_free . r name )
    ( string_free . r unit )
}

@ bench_row_name BenchRow r → s { ^ ( string_data . r name ) }

// Run `body` through std/bench and package it as a row with a throughput
// figure in `unit` (e.g. `MB/s`, `M/s`, `MFLOP/s`).
@ bench_thpt s name i units_per_op s unit ( @ v ) body → BenchRow {
    : BenchResult br ( bench_auto name body )
    : i nspo ( bench_result_ns_per_op br )
    : i apo ( bench_result_allocs_per_op br )
    : i thpt ? > nspo 0 / * units_per_op 1000 nspo 0
    ( bench_result_free br )
    // `body` is moved in and, after bench_auto, can never run again — release
    // its captured environment (decompose the fat pointer, free the env slot).
    : *u env # *u body 1
    ( nurl_free # s env )
    ^ @ BenchRow { ( string_from name ) nspo apo thpt ( string_from unit ) }
}

@ __pad_right s txt i w → String {
    : String o ( string_from txt )
    : ~ i pad - w ( nurl_str_len txt )
    ~ > pad 0 { ( string_push_char o 32 ) = pad - pad 1 }
    ^ o
}

@ __pad_left s txt i w → String {
    : String o ( string_new )
    : ~ i pad - w ( nurl_str_len txt )
    ~ > pad 0 { ( string_push_char o 32 ) = pad - pad 1 }
    ( string_push_str o txt )
    ^ o
}

// "  sha256          1234 MB/s     (   85 ns/op, 3 allocs/op)"
@ bench_row_print BenchRow r → v {
    : String line ( string_from `  ` )
    : String nm ( __pad_right ( string_data . r name ) 16 )
    ( string_push_str line ( string_data nm ) )
    ( string_free nm )
    : String tv ( __pad_left ( nurl_str_int . r thpt ) 8 )
    ( string_push_str line ( string_data tv ) )
    ( string_free tv )
    ( string_push_char line 32 )
    : String u ( __pad_right ( string_data . r unit ) 8 )
    ( string_push_str line ( string_data u ) )
    ( string_free u )
    ( string_push_str line `(` )
    ( string_push_str line ( nurl_str_int . r ns_per_op ) )
    ( string_push_str line ` ns/op, ` )
    ( string_push_str line ( nurl_str_int . r allocs_per_op ) )
    ( string_push_str line ` allocs/op)` )
    ( nurl_print ( string_data line ) )
    ( nurl_print `\n` )
    ( string_free line )
}

// one JSON object per row (no trailing comma handling here — the caller
// joins them into an array)
@ bench_row_json BenchRow r → String {
    : String o ( string_from `{"name":"` )
    ( string_push_str o ( string_data . r name ) )
    ( string_push_str o `","ns_per_op":` )
    ( string_push_str o ( nurl_str_int . r ns_per_op ) )
    ( string_push_str o `,"allocs_per_op":` )
    ( string_push_str o ( nurl_str_int . r allocs_per_op ) )
    ( string_push_str o `,"throughput":` )
    ( string_push_str o ( nurl_str_int . r thpt ) )
    ( string_push_str o `,"unit":"` )
    ( string_push_str o ( string_data . r unit ) )
    ( string_push_str o `"}` )
    ^ o
}
