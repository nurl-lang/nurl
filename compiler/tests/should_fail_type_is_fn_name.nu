// should_fail_type_is_fn_name.nu — using a function / FFI symbol name where a
// TYPE is expected leaked an undefined `%name`; a name in scope that is not a
// `%`-type is now reported as an unknown type.
& `libc` @ rand → i

@ f rand x → i { ^ 0 }

@ main → i { ^ 0 }
