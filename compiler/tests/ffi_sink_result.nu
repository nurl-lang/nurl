// `→ sink s` on a foreign function: the C function hands its result over
// (a string it allocated), and the binding it lands in owns it — released
// at scope exit, handed on to string_adopt, or dropped as a temporary.
// Nothing frees it by hand; the sanitizer run checks that nothing leaks
// and nothing is freed twice.
$ `stdlib/core/string.nu`

& `c` @ strdup s src → sink s

unsafe @ dup_len s x → i {
    : s d ( strdup x )
    ^ ( nurl_str_len d )
}

unsafe @ adopt s x → String {
    : s d ( strdup x )
    ^ ( string_adopt d )
}

unsafe @ main → i {
    ( nurl_println_int ( dup_len `hello` ) )
    : String a ( adopt `world` )
    ( nurl_println ( string_data a ) )
    : String b ( string_from ( strdup `as a temporary` ) )
    ( nurl_println ( string_data b ) )
    : ~ i k 0
    : ~ i total 0
    ~ < k 1000 {
        : s t ( strdup `in a loop` )
        = total + total ( nurl_str_len t )
        = k + k 1
    }
    ( nurl_println_int total )
    ^ 0
}
