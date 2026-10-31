// field_of_call_result_leaks: a field that owns something, read out of a call's result (`^ . ( mk ) backend`, `: String b . ( mk ) backend`, `( len . ( mk ) name )`, `@ W { . ( mk ) device }`), left the rest of that temporary undropped — its other fields leaked — and the read itself was taken for a view of the temporary, so nothing dropped it either. (A field that owns nothing already dropped the temporary, h232.)
// Closed: the field leaves the temporary, whose rest — its value with that field emptied — is dropped where it is read; the field is a value of its own (copied when the call only lent its result) that a binding, a return, an argument or a literal takes over.
// main's compiler: LeakSanitizer, the other field's String (embed's GET /health through `^ . ( locked_get … ) backend`).
// map: §7.1 | A2 | runs-clean | h266 | owned field read from a call result; rest of temporary never dropped
$ `stdlib/core/io.nu`
$ `stdlib/core/string.nu`

: Stat { b ok String backend String device i n }
: W { String s }

@ mk → Stat { ^ @ Stat { T ( string_from `cpu` ) ( string_from `host` ) 3 } }

@ backend → String { ^ . ( mk ) backend }

@ len String x → i { ^ ( string_len x ) }

@ main → i {
    : String b ( backend )
    : String c . ( mk ) device
    : W w @ W { . ( mk ) device }
    ( nurl_println_int + + + ( string_len b ) ( string_len c ) ( string_len . w s ) ( len . ( mk ) backend ) )
    ^ 0
}
