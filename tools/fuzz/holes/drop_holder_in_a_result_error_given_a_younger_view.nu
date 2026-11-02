// drop_holder_in_a_result_error_given_a_younger_view: agora #363 — a `!i W` result declared before a String, its error side given a W viewing it: W's `% Drop` reads the view after the String, younger, is freed
// Closed: __dmrv_walk asks a library handle's type arguments as parsed types (__libh_targ: `?W` is an option of W, not `%?W`), counts a program's own `S_drop` hook on a plain struct whose fields may hold a view as a destructor that reads them, and walks a result's error side as well as its payload (agora #363).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #363: a `!i W` result declared before a String, its error side given a W viewing it
$ `stdlib/core/string.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : ~ ! i W r @ !i W { T 0 }
    : String b ( string_from `a string younger than the result that holds a view of it` )
    = r @ !i W { F @ W { ( string_data b ) } }
    ^ 0
}
