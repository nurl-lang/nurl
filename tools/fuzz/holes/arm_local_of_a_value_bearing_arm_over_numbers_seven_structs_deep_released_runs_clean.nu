// arm_local_of_a_value_bearing_arm_over_numbers_seven_structs_deep_released_runs_clean: a value-bearing `?` arm whose value is a struct of numbers seven structs deep, with an arm-local String
// Closed: the numbers-only walk has no depth budget (a value's by-value parts are a finite tree) and keeps each struct's answer (agora #740).
// main 3b63ee3b: accepted — and leaked: the arm's local was never released.
// map: §7.1 | A2 | runs-clean | - | agora #740: an arm local beside numbers seven structs deep released
$ `stdlib/core/string.nu`

: L1 { i n }
: L2 { L1 a }
: L3 { L2 a }
: L4 { L3 a }
: L5 { L4 a }
: L6 { L5 a }
: L7 { L6 a }

@ main → i {
    : ~ i acc 0
    : ~ i k 0
    ~ < k 4 {
        : L7 r ? > k 1 { : String t ( string_from `an arm-local string long enough to sit on the heap, surely` ) @ L7 { @ L6 { @ L5 { @ L4 { @ L3 { @ L2 { @ L1 { ( string_len t ) } } } } } } } } { @ L7 { @ L6 { @ L5 { @ L4 { @ L3 { @ L2 { @ L1 { 0 } } } } } } } }
        = acc + acc . . . . . . . r a a a a a a n
        = k + k 1
    }
    ( nurl_println_int acc )
    ^ 0
}
