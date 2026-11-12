// struct_holding_a_boxed_enum_never_dropped: a struct with a field of an enum whose payload is a boxed plain struct (`: | Shade { Light Mix Pt }`, `: W { Shade s String t }`) was dropped by nobody — the enum's box leaked, and so did every other owned field (agora #787).
// Closed: such an enum is no handle (__is_handle_enum: a boxed plain struct does not copy as one), so a struct holding it is no handle either; it gets the drop the compiler writes field by field (__needs_synth_drop), as for a struct holding a `% Drop` value, and is moved, never copied.
// main (before this PR): LeakSanitizer reported the box and the String (40 bytes in 3 blocks).
// map: §7.6 | A2 | runs-clean | - | a struct holding an enum with a boxed plain-struct payload, a String beside it — never dropped, leak
$ `stdlib/core/string.nu`

: Pt { i x i y }

: | Shade { Light Mix Pt }

: W { Shade s String t }

@ main → i {
    : W w @ W { @ Shade { Mix @ Pt { 40 0 } } ( string_from `a heap string, long enough for its own buffer` ) }
    ^ - ( string_len . w t ) 45
}
