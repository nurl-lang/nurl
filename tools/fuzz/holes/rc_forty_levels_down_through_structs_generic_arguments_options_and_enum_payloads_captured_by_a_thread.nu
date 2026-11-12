// rc_forty_levels_down_through_structs_generic_arguments_options_and_enum_payloads_captured_by_a_thread: an `Rc` at the bottom of a nest forty levels deep — struct fields, the argument of a generic struct, options and enum payloads, in turn — and the value at the top is handed to a function that moves it into a `thread_spawn` closure.
// main: accepted — every kind of level counted against the Send/Sync walk's budget of ten, and below it the walk answered "nothing found" (the twelve-struct spelling, rc_twelve_structs_down_captured_by_a_thread, faults under ASan).
// map: §6.5 | A3 | rejected | - | an `Rc` forty levels down through fields, generic arguments, options and enum payloads, captured by a spawned closure: no depth is too deep for the derivation to read (agora #711)
$ `stdlib/std/rc.nu`
$ `stdlib/std/thread.nu`
$ `stdlib/core/option.nu`

: Wrap [T] { T x i n }
: D0 { ( Rc i ) r i tag }
: D1 { D0 a }
: D2 { ( Wrap D1 ) a }
: D3 { ? D2 a i n }
: | E4 { Got4 D3 Nope4 }
: D4 { E4 a }
: D5 { D4 a }
: D6 { ( Wrap D5 ) a }
: D7 { ? D6 a i n }
: | E8 { Got8 D7 Nope8 }
: D8 { E8 a }
: D9 { D8 a }
: D10 { ( Wrap D9 ) a }
: D11 { ? D10 a i n }
: | E12 { Got12 D11 Nope12 }
: D12 { E12 a }
: D13 { D12 a }
: D14 { ( Wrap D13 ) a }
: D15 { ? D14 a i n }
: | E16 { Got16 D15 Nope16 }
: D16 { E16 a }
: D17 { D16 a }
: D18 { ( Wrap D17 ) a }
: D19 { ? D18 a i n }
: | E20 { Got20 D19 Nope20 }
: D20 { E20 a }
: D21 { D20 a }
: D22 { ( Wrap D21 ) a }
: D23 { ? D22 a i n }

@ look D23 x → v {}

@ run sink D23 x → v {
    ?? ( thread_spawn \ → v { ( look x ) } ) {
        T t → { ( thread_join t ) }
        F _ → {}
    }
}

@ main → i { ^ 0 }
