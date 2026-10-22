// closure_capture_drop_field_handed_on.nu
// A struct with a `% Drop` field, captured by a closure that a call is
// handed. The env's drop needs the struct's drop, which the compiler writes
// field by field the first time it is owned — and it printed that
// `define` while `main` was being written: the module held `main` up to
// the capture and nothing after it (nurlc exited 0; clang rejected the IR,
// or, linked, `main` never ran its tail). The drop is emitted at module end
// now. Each line below must print, and the drop must run once.

$ `stdlib/core/string.nu`

: R { i n }

% Drop R { @ drop R x → v { ( puts `drop R` ) } }

: Holder { R s i k }

@ use R r → v { ( puts ( nurl_str_cat `use ` ( nurl_str_int . r n ) ) ) }

@ run ( @ v ) f → v { ( f ) ( f ) }

@ main → i {
    : Holder h @ Holder { @ R { 7 } 1 }
    : ( @ v ) body \ → v { ( use . h s ) }
    ( run body )
    ( puts `after the call` )
    ^ 0
}
