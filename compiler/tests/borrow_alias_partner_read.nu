// borrow_alias_partner_read.nu — `= z a` hands `a`'s handle to `z`: the two
// share one buffer on that path (alias partners). Reading `a` stays fine
// while the buffer lives, but once `z` is consumed, `a` names freed memory
// on the path that aliased — a silent use-after-free (it read 24 for a
// 5-byte string). It is an error now (docs/MEMORY.md §2.1).
//
// CONTROLS — none of these may be flagged:
//   * the double-buffer swap (`: tmp cur` `= cur nxt` `= nxt tmp`): the
//     reassigned name had already handed its handle on, so nothing drops;
//   * a link made on one arm of a `?` is inert on the other;
//   * a loop that re-binds a payload each pass: last pass's partner is not
//     this pass's.

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`

@ positive i c → i {
    : String a ( string_from `hello` )
    : ~ String z ( string_from `x` )
    ? > c 0 { = z a } {}
    ( string_free z )
    ^ ( string_len a )
}

@ swap_control → i {
    : ~ ( Vec i ) cur ( vec_new [i] )
    : ~ ( Vec i ) nxt ( vec_new [i] )
    : ~ i k 0
    ~ < k 3 {
        ( vec_clear [i] nxt )
        ( vec_push [i] nxt k )
        : ( Vec i ) tmp cur
        = cur nxt
        = nxt tmp
        = k + k 1
    }
    ^ ( vec_len [i] cur )
}

@ arm_control i c → i {
    : String a ( string_from `hello` )
    : ~ String z ( string_from `x` )
    ? > c 0 { = z a ^ ( string_len z ) } {
        ( string_free z )
        ^ ( string_len a )
    }
}

@ loop_payload_control → i {
    : ~ String out ( string_from `start` )
    : ~ i k 0
    ~ < k 3 {
        : ?String got @ ?String { T ( string_from `next` ) }
        ?? got {
            T g → { ( string_free out ) = out g }
            F → {}
        }
        = k + k 1
    }
    ^ ( string_len out )
}

@ main → i {
    ^ + + + ( positive 1 ) ( swap_control ) ( arm_control 0 ) ( loop_payload_control )
}
