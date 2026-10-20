// stdlib/core/rcbox.nu — the storage behind an opaque library handle.
//
// A module that hands out a one-word handle over state of its own
// (`: Regex { s ctl }`, `: Sha256 { s ctl }`) keeps that state in an
// rcbox: one heap block, `[ i64 owners ][ T value ]` (Arc's layout), whose
// last owner drops the value — its String / Vec / handle fields, and its
// own `% Drop` if it has one — and frees the block. The handle becomes a
// library handle (docs/MEMORY.md §7.6) with two lines:
//
//   @ Regex_share Regex r → Regex { ^ @ Regex { # s ( rcbox_share # i . r ctl ) } }
//   @ Regex_drop sink Regex r → v { ( mem_forget r ) ( rcbox_release [RegexImpl] # i . r ctl ) }
//
// and every copy of it (a struct field, a closure capture, a Vec element)
// is the same state, as a copied pointer was, while nobody frees it by
// hand. The block pointer travels as an `i`: it is the handle's to own,
// never a string anything else would release.
//
// These primitives are raw (spec §3.3d): outside the standard library only
// an `unsafe` function may call them. A program's own handle wraps an
// `Arc` instead (stdlib/std/arc.nu), whose share and drop hooks are safe
// code (docs/MEMORY.md §7.6).
//
// API:
//
//   ( rcbox_new     [T] T x )  → i     a block with one owner holding x
//   ( rcbox_zero    [T] )      → i     …holding a zeroed T, for a constructor
//                                       that fills it in place (rcbox_ptr)
//   ( rcbox_ptr     [T] i p )  → *T    the value in place (borrowed)
//   ( rcbox_share   i p )      → i     one more owner; p back
//   ( rcbox_release [T] i p )  → v     one owner fewer; the last drops the value

// The owner count: one more (the old count back), one fewer (1 when the
// caller was the last owner). A count of 1 skips the locked RMW.
& `c` @ nurl_rc_share sync *u p → i

& `c` @ nurl_rc_release sync *u p → i

: RcBox [T] {
    i owners
    T value
}

@ rcbox_new [T] T x → i {
    : *( RcBox T ) b # *( RcBox T ) ( nurl_alloc Z ( RcBox T ) )
    = . b owners 1
    = . b value x
    ^ # i b
}

@ rcbox_zero [T] → i {
    : *( RcBox T ) b # *( RcBox T ) ( nurl_zalloc Z ( RcBox T ) )
    = . b owners 1
    ^ # i b
}

@ rcbox_ptr [T] i p → *T {
    ^ # *T + p 8
}

@ rcbox_share i p → i {
    ? != 0 p { : i _old ( nurl_rc_share # *u p ) } {}
    ^ p
}

@ rcbox_release [T] i p → v {
    ? == 0 p {} {
        ? != 0 ( nurl_rc_release # *u p ) {
            : *( RcBox T ) b # *( RcBox T ) p
            : T v . b value
            ( mem_take v )
            ( nurl_free # s p )
        } {}
    }
}

// ── Shared: the handle over an rcbox ───────────────────────────────
//
// A module's handle holds one, so its hooks hold no release of their own:
//
//   : Regex { ( Shared RegexImpl ) ctl }
//   @ Regex_share Regex r → Regex { ^ @ Regex { ( shared_clone [RegexImpl] . r ctl ) } }
//   @ Regex_drop sink Regex r → v {}
//
// The field goes with the handle (Shared_drop: one owner fewer, and the
// last drops the value and frees the block). The compiler reads the share
// hook's `shared_clone [T]` to learn the state a handle holds, for the
// thread-shared cycle rules (docs/MEMORY.md §7.7). Making one, reaching
// into one and a null one are raw (spec §3.3d): the standard library's
// own, or an `unsafe` function's.
//
//   ( shared_new   [T] x )   → ( Shared T )   one owner, holding x
//   ( shared_zero  [T] )     → ( Shared T )   …holding a zeroed T, filled in place
//   ( shared_null  [T] )     → ( Shared T )   no block (a handle not made yet)
//   ( shared_ptr   [T] h )   → *T             the value in place (borrowed)
//   ( shared_addr  [T] h )   → i              the block's address (0: null)
//   ( shared_clone [T] h )   → ( Shared T )   one more owner of the same block

: Shared [T] { s ctl }

// Built here rather than through rcbox_new: a generic cannot be `inline`,
// and the extra call copied the whole value once more on its way in.
@ shared_new [T] T x → ( Shared T ) {
    : *( RcBox T ) b # *( RcBox T ) ( nurl_alloc Z ( RcBox T ) )
    = . b owners 1
    = . b value x
    ^ @ ( Shared T ) { # s b }
}

@ shared_zero [T] → ( Shared T ) {
    : *( RcBox T ) b # *( RcBox T ) ( nurl_zalloc Z ( RcBox T ) )
    = . b owners 1
    ^ @ ( Shared T ) { # s b }
}

@ shared_null [T] → ( Shared T ) { ^ @ ( Shared T ) { # s 0 } }

@ shared_ptr [T] ( Shared T ) h → *T { ^ ( rcbox_ptr [T] # i . h ctl ) }

@ shared_addr [T] ( Shared T ) h → i { ^ # i . h ctl }

@ shared_clone [T] ( Shared T ) h → ( Shared T ) { ^ @ ( Shared T ) { # s ( rcbox_share # i . h ctl ) } }

@ Shared_share [T] ( Shared T ) h → ( Shared T ) { ^ ( shared_clone [T] h ) }

@ Shared_drop [T] sink ( Shared T ) h → v {
    ( mem_forget h )
    ( rcbox_release [T] # i . h ctl )
}

// One owner as a word, for a plain value that carries a handle without
// being one (std/net.nu's TcpConn keeps its TLS connection so): the word
// owns, and shared_from_word takes the owner back.
@ shared_into_word [T] sink ( Shared T ) h → i {
    : i w # i . h ctl
    ( mem_forget h )
    ^ w
}

@ shared_from_word [T] i w → ( Shared T ) { ^ @ ( Shared T ) { # s w } }

& `c` @ nurl_once_slot i id i candidate → i

// A value the whole program shares, built lazily by whichever thread gets
// there first: `h` is offered for the runtime's publish-once slot `slot`
// (the slot registry is in stdlib/std/tls_server.nu). The first one
// published there stays for the program's life; a later one is released
// here. Every caller gets the published value, in place.
@ shared_publish_once [T] i slot sink ( Shared T ) h → *T {
    : i mine # i . h ctl
    : i won ( nurl_once_slot slot mine )
    ? == won mine { ( mem_forget h ) } {}
    ^ ( rcbox_ptr [T] won )
}
