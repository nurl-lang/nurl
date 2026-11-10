// closure_bound_in_a_value_block_and_handed_out_as_its_value: `: ( @ i i ) g { : ( @ i i ) f \ … tag … f }`, straight and in a loop body, handed back and handed to a sink; the same assigned (`= f { … h }`); and a block that binds a closure and ends in a call returning another.
// Closed: a `:` binding's value block whose tail is a closure binding the block made takes the env over from it, as `: g f` does (__blk_tail_closure), and a `:` settles the env its own literal made (`__last_closure_env__`) so that the `:` around it does not read it as its own right-hand side's. The block's binding kept its env and the new binding was given the same one: both released it (agora #627).
// main 2498b4e: accepted; AddressSanitizer: heap-use-after-free in the closure's drop.
// map: §7.5 | A2 | runs-clean | - | agora #627: a capturing closure bound in a value block and handed out as the block's value
$ `stdlib/core/string.nu`

@ mk String tag → ( @ i i ) { ^ \ i x → i { ^ + x ( string_len tag ) } }

@ make String tag → ( @ i i ) {
    : ( @ i i ) g { : ( @ i i ) f \ i x → i { ^ + x ( string_len tag ) } f }
    ^ g
}

@ apply sink ( @ i i ) f i a → i { ^ ( f a ) }

@ main → i {
    : String tag ( string_from `a captured tag long enough for a heap buffer` )
    : ( @ i i ) g { : ( @ i i ) f \ i x → i { ^ + x ( string_len tag ) } f }
    : ~ i total ( g 1 )
    : ~ i k 0
    ~ < k 3 {
        : ( @ i i ) h { : ( @ i i ) f \ i x → i { ^ + + x k ( string_len tag ) } f }
        = total + total ( h k )
        = k + k 1
    }
    : ( @ i i ) r ( make tag )
    = total + total ( r 1 )
    : ( @ i i ) s { : ( @ i i ) f \ i x → i { ^ + + x 2 ( string_len tag ) } f }
    = total + total ( apply s 1 )
    : ( @ i i ) c { : ( @ i i ) f \ i x → i { ^ + + x 100 ( string_len tag ) } : i n ( f 1 ) ( mk tag ) }
    = total + total ( c 1 )
    : ~ ( @ i i ) a \ i x → i { ^ + x 1 }
    = a { : ( @ i i ) h \ i x → i { ^ + x ( string_len tag ) } h }
    ( nurl_println_int + total ( a 1 ) )
    ^ 0
}
