// string_eighteen_structs_down_forged_from_an_integer_by_a_cast: `: L1 { String s }`, `: L2 { L1 a }` … `: L18 { L17 a }`; `: L18 h # L18 4096` in safe code, then the String read
// Closed: the walk that asks whether a cast's target holds an address reads the type whole (by-value nesting is a finite tree), where a budget of sixteen levels answered "none" and recorded that for every type above (agora #721).
// main 3b63ee3b: accepted; AddressSanitizer: SEGV.
// map: §6.2 | B | rejected | - | agora #721: a String eighteen structs down forged from an integer by a cast
$ `stdlib/core/string.nu`

: L1 { String s }
: L2 { L1 a }
: L3 { L2 a }
: L4 { L3 a }
: L5 { L4 a }
: L6 { L5 a }
: L7 { L6 a }
: L8 { L7 a }
: L9 { L8 a }
: L10 { L9 a }
: L11 { L10 a }
: L12 { L11 a }
: L13 { L12 a }
: L14 { L13 a }
: L15 { L14 a }
: L16 { L15 a }
: L17 { L16 a }
: L18 { L17 a }

@ main → i {
    : L18 h # L18 4096
    ( nurl_println_int ( string_len . . . . . . . . . . . . . . . . . . h a a a a a a a a a a a a a a a a a s ) )
    ^ 0
}
