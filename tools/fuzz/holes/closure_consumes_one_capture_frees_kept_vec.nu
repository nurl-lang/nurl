// closure_consumes_one_capture_frees_kept_vec: agora #247 — a closure called in its own frame, consuming one capture, freed a Vec it only read: the frame read the Vec after the closure ended (closure_consumes_one_capture_frees_kept_vec).
// Closed: a closure whose body releases one capture moves only that one into its env (g_env_released), with what a spawn takes over (g_env_moved); a handle the frame still uses stays a view, which the spawn's adopt shares or copies (gen_env_vtable, gen_env_allocation; agora #247).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.5 | A2 | runs-clean | - | agora #247: a closure called in its own frame, consuming one capture, freed a Vec it only read: the frame read the Vec after the closure ended
$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ consume sink String s → i { ^ ( string_len s ) }

@ main → i {
    : ( Vec i ) xs ( vec_new [i] )
    ( vec_push [i] xs 7 )
    : String owned ( string_from `hello` )
    {
        : ( @ i ) f \ → i { ^ + ( consume owned ) ( vec_len [i] xs ) }
        ( nurl_print_int ( f ) )
    }
    ( nurl_print_int ( vec_len [i] xs ) )
    ^ 0
}
