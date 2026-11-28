// in_param_without_a_copy_lent_back_by_a_bound_literal_runs_clean: a value that cannot be copied (a struct holding a trait object), named whole in a bound literal handed back, is lent as in `^ @ Wrap { p 2 }`.
// AGORA-1008: the bound spelling hands back the literal as written, so no copy is asked for.
// map: §7.6 | A2 | runs-clean | - | AGORA-1008: an uncopyable `in` parameter handed back in a bound literal is lent
% Speaker [T] { @ speak T self → i }

: Dog { i pitch }

% Speaker Dog { @ speak Dog d → i { ^ . d pitch } }

: Pet { % Speaker s }

: Wrap { Pet p i n }

@ wrap Pet p → Wrap {
    : Wrap w @ Wrap { p 2 }
    ^ w
}

@ main → i {
    : Pet a @ Pet { ( dyn Speaker @ Dog { 5 } ) }
    : Wrap w ( wrap a )
    ( nurl_println_int + ( speak . . w p s ) . w n )
    ( nurl_println_int ( speak . a s ) )
    ^ 0
}
