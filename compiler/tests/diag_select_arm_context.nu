// diag_select_arm_context.nu — a select arm whose element type disagrees
// with the channel, and where the compiler says it.
//
// A select lowers to a whole generated program — a poll loop, a shared
// waiter, one `chan_try_recv` per arm — which is then re-lexed through a
// sub-lexer. Every check inside that re-parse reports against THAT text,
// so an arm's type error printed
//
//     <select>:4:127: error: …
//
// with a caret into a line the author never wrote, naming no file, no
// line of real source, and no '??'. Which arm of which select was left
// entirely to the reader.
//
// `<dynsig>` — the other synthetic buffer in the compiler — had the same
// problem and already had the cure: `g_diag_ctx`, a suffix appended to
// every diagnostic raised while the re-parse is running, naming the real
// thing. This is that cure at the second buffer, carrying the '??'s own
// position, which gen_match has always captured for the borrow checker's
// structural markers and now hands to gen_select.
//
// The synthetic location stays: the caret genuinely points at the
// lowered call, and moving it would mean threading a position through
// every token of generated text. What was missing was the sentence that
// tells the reader where to look instead.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) c ( chan_new [i] )
    ?? {
        [s] c → o {}
        _ → {}
    }
    ( chan_free [i] c )
    ^ 0
}
