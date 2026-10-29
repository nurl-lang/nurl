// H571: agora #158 — a result whose payload or error is an option (struct_field_result_with_an_option_error_matched).
// Closed: the result registers its twin past the inner braces (agora #158).
// v0.80.0: accepted; LeakSanitizer reported a leak.
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ mk → String { ^ ( string_from `a string long enough to own a heap buffer here` ) }

: R { String s i pad }
: RV { ( Vec String ) xs i pad }

@ run ( @ v ) f → v { ( f ) }

: S { ! String ? i r i pad }

@ main → i {
    : S s @ S { @ !String ? i { T ( mk ) } 0 }
    ?? . s r { T x → { ( nurl_println ( string_data x ) ) } F e → {} }
    ^ 0
}
