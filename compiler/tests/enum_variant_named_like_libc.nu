// An enum variant is its tag, a number in the generated code — the
// module holds no symbol for it (AGORA-853). While each variant was a
// global `@<name>`, one named like something the C runtime declares
// (`malloc`, `free`, `write`, `read`, `exit`) redefined that symbol: clang
// refused the module ("redefinition of global '@malloc'") with no NURL
// source position, and one named like a libc data symbol nurlc does not
// declare (`environ`, `stdin`) would have been linked in its place.

$ `stdlib/core/string.nu`

: | Op { write read malloc free exit }

: | Stream { stdin stdout stderr environ errno }

@ op_name Op o → s {
    ^ ?? o {
        write → `write`
        read → `read`
        malloc → `malloc`
        free → `free`
        exit → `exit`
    }
}

@ stream_no Stream st → i {
    ^ ?? st {
        stdin → 0
        stdout → 1
        stderr → 2
        environ | errno → 9
    }
}

@ main → i {
    // The runtime's own malloc / free / write still run: a String is built,
    // grown and printed, and dropped at the end.
    : String t ( string_from ( op_name malloc ) )
    ( string_push_str t ` ` )
    ( string_push_str t ( op_name free ) )
    ( string_push_str t ` ` )
    ( string_push_str t ( op_name write ) )
    ( string_push_str t ` ` )
    ( string_push_str t ( op_name read ) )
    ( string_push_str t ` ` )
    ( string_push_str t ( op_name exit ) )
    ( nurl_println ( string_data t ) )
    ( nurl_println_int + + + + ( stream_no stdin ) ( stream_no stdout ) ( stream_no stderr ) ( stream_no environ ) ( stream_no errno ) )
    : Op o exit
    ( nurl_println_int ? == # i o # i exit 1 0 )
    ^ 0
}
