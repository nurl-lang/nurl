// drop_holder_in_a_map_of_options_given_a_younger_view: agora #363 — a `( HashMap i ?W )` declared before a String, given a W viewing it: W's `% Drop` reads the view, and the String, younger, is freed first at the scope's end
// Closed: __dmrv_walk asks a library handle's type arguments as parsed types (__libh_targ: `?W` is an option of W, not `%?W`), counts a program's own `S_drop` hook on a plain struct whose fields may hold a view as a destructor that reads them, and walks a result's error side as well as its payload (agora #363).
// main: accepted; AddressSanitizer reported heap-use-after-free.
// map: §7.6 | A2 | rejected | - | agora #363: a `( HashMap i ?W )` declared before a String, given a W viewing it
$ `stdlib/core/string.nu`
$ `stdlib/std/hashmap.nu`

: W { s v }

% Drop W { @ drop W self → v { ( nurl_println . self v ) } }

@ main → i {
    : ( HashMap i ? W ) m ( map_new [i ? W] )
    : String b ( string_from `a string younger than the map that holds a view of it` )
    : ?? W old ( map_set [i ? W] m 1 @ ?W { T @ W { ( string_data b ) } } \ i k → i { ^ k } \ i x i y → b { ^ == x y } )
    ^ 0
}
