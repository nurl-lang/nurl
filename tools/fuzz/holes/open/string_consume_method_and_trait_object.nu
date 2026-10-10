// OPEN in 0.72.0 — a method's `sink s` parameter, called statically and through a trait object: leaked, or a literal freed.
// Ka's `eat` only reads `x`; Kb's adopts it with string_adopt. Each is called through %Taker and directly,
// with an owned string, a literal and a temporary: through Ka the owned string and the temporary leak
// (a `sink s` the callee only reads is never released); through Kb the literal is adopted and released.
// ASan: SEGV in the allocator's Deallocate (Kb's eat releasing the literal `lit`, static memory).
$ `stdlib/core/string.nu`

: Ka { i n }
: Kb { i n }

% Taker [T] { @ eat T self sink s x → i }

% Taker Ka { @ eat Ka b sink s x → i { ^ + . b n ( strlen x ) } }

% Taker Kb { @ eat Kb b sink s x → i { : String t ( string_adopt x ) ^ + . b n ( string_len t ) } }

@ use_it %Taker d → i {
    : s m ( nurl_str_cat `ab` `cd` )
    : i r ( eat d m )
    ^ + + r ( eat d `lit` ) ( eat d ( nurl_str_cat `x` `y` ) )
}

@ main → i {
    : Ka a @ Ka { 10 }
    : Kb b @ Kb { 20 }
    ( nurl_println_int + ( use_it ( dyn Taker a ) ) ( use_it ( dyn Taker b ) ) )
    ( nurl_println_int + ( eat a `lit` ) ( eat b ( nurl_str_cat `p` `q` ) ) )
    ^ 0
}
