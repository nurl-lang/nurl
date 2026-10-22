// diag_marker_unsafe_on_checked_impl.nu
// `unsafe` on an impl means "take this on trust", and only a `% Send` or
// `% Sync` assertion is taken on trust. On any other impl — a negative
// marker, `% Frozen`, a trait with methods — it would be a promise about
// nothing, so it is an error rather than a silent no-op (it used to leak
// onto the next foreign declaration and make it raw).

$ `stdlib/core/marker.nu`

: Db { s handle }

unsafe % NotSend Db {}

@ main → i { ^ 0 }
