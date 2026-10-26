// diag_send_dyn_impl_breaks_promise.nu — `% Job [T] : Send` promises that
// a `%Job` object may move to another thread, so every type implementing
// `Job` is held to Send where its impl is, by the derivation (no impl
// block of `Send` says it). `Holder` reaches an Rc: the impl is rejected
// at its `%`, naming the Rc. Before, the supertrait demanded a `% Send
// Holder { }` block, and the message advised writing one.
$ `stdlib/std/rc.nu`

: Holder { ( Rc i ) r }

% Job [T] : Send { @ run T self → i }

% Job Holder { @ run Holder h → i { ^ ( rc_get [i] . h r ) } }

@ main → i { ^ 0 }
