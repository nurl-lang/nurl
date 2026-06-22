// should_fail_unknown_type_ffi.nu — an FFI declaration whose return type
// names no declared type used to leak `%Zorp` into the IR (only clang/llvm-as
// rejected it). check_type_known now reports it at the source.
& `libc` @ foo → Zorp

@ main → i { ^ 0 }
