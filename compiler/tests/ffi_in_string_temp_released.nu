// ffi_in_string_temp_released.nu — a string made in an argument and handed
// to a C function that only reads it is released after the call.
//
// A foreign function's pointer parameter was assumed to keep or free what
// it is given unless its declaration said otherwise, and nothing in the
// declarations of remove, unlink, mkdir, access, stat … said otherwise:
// every computed path handed to file_delete, file_exists, dir_create (or
// any wrapper of them) was left to nobody. An `in` parameter is borrowed
// for the call — read, neither kept nor freed — and the libc path
// functions say so now.

$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`

& `libc` @ nurl_alloc_count → i

& `libc` @ nurl_free_count → i

// `name` under the platform's temp directory (env_temp_dir).
@ tmp_path s name → String {
    : String p ( env_temp_dir )
    ( string_push_char p 47 )
    ( string_push_str p name )
    ^ p
}

unsafe @ live → i { ^ - ( nurl_alloc_count ) ( nurl_free_count ) }

@ round i k → i {
    // Scratch paths under the platform's temp directory: on Windows /tmp
    // is a directory on the current drive that exists only if something
    // made it first (agora #306).
    : String tp0 ( tmp_path `nurl_ffi_in_` )
    : ~ i n 0
    ? ( file_exists ( nurl_str_cat ( string_data tp0 ) ( nurl_str_int k ) ) ) { = n + n 1 } {}
    ?? ( file_delete ( nurl_str_cat ( string_data tp0 ) ( nurl_str_int k ) ) ) { T _ → { = n + n 1 } F _ → {} }
    ^ n
}

@ main → i {
    : i r0 ( round 0 )
    : i l0 ( live )
    : ~ i k 0
    : ~ i hits 0
    ~ < k 100 { = hits + hits ( round k ) = k + k 1 }
    ( nurl_println ( nurl_str_cat `hits ` ( nurl_str_int + r0 hits ) ) )
    ( nurl_println ? == l0 ( live ) `live allocations: steady` ( nurl_str_cat `live allocations grew by ` ( nurl_str_int - ( live ) l0 ) ) )
    ^ 0
}
