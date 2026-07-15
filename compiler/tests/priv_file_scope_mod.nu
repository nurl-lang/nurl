// The imported half of priv_file_scope: its OWN private `__pick`, and a
// public function that calls it — proving the mod's calls bind to the mod's
// private even when the importing file defines a `__pick` of its own.
@ __pick → i {
    ^ 1
}

@ mod_pick → i {
    ^ ( __pick )
}
