// should_fail_ffi_no_name.nu — an FFI declaration whose `@` is not followed
// by an identifier name used to emit `declare T @<garbage>(…)`.
& `libc` @

@ foo → i

@ main → i { ^ 0 }
