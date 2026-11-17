// slice_temporary_of_strings_handed_to_a_reader_runs_clean: `( lns ( mks ) )`, a slice of Strings: its elements go with it
// Closed (agora #891): a slice a call made, handed straight to another call, is a temporary of the caller's: released after the call, its elements first (`__slice_drop__String`, asked for with its `__dropifv_`).
// main 2a7b1153: LeakSanitizer reported the slice and its Strings never released.
// map: §7.6 | A2 | runs-clean | - | AGORA-891: `( lns ( mks ) )`, a slice of Strings: its elements go with it
$ `stdlib/core/vec.nu`
$ `stdlib/core/slice.nu`
$ `stdlib/core/string.nu`

@ mks → [String { ^ [String | ( string_from `an element string long enough for a heap buffer` ) ( string_from `b` )] }
@ lns [String a → i { ^ . a 1 }
@ main → i { ( nurl_println_int ( lns ( mks ) ) ) ^ 0 }
