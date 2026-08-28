// swim_table.nu — offline tests for the SWIM member-table state machine
// (stdlib/std/swim.nu). Deterministic: suspect_timeout_ms = 0 makes the
// Suspect→Dead sweep fire immediately, so no wall-clock dependency.
//
// Covers: add, local suspect, timeout sweep to Dead, self-refutation
// (incarnation bump), and gossip precedence (higher-incarnation Alive
// revives a Dead member; a stale Suspect is rejected).

$ `stdlib/core/string.nu`
$ `stdlib/core/vec.nu`
$ `stdlib/std/swim.nu`

@ pb s label b v → v { ( nurl_print label ) ( nurl_print ? v `T\n` `F\n` ) }

@ pst s label i st → v {
    ( nurl_print label )
    ( nurl_print ? == st 0 `alive\n` ? == st 1 `suspect\n` ? == st 2 `dead\n` `?\n` )
}

@ apply_m * MemberTable t s host i port i inc MemberState state s label → v {
    : Member up ( member_new host port inc state )
    ( pb label ( mtable_apply t up ) )
    ( member_free up )
}

@ main → i {
    : *MemberTable t ( mtable_new `self` 7000 0 )

    // ── add A (alive) ────────────────────────────────────────────
    ( apply_m t `A` 8001 0 @ MemberState { MAlive } `add A alive: ` )
    ( pst `A state: ` ( mtable_state_of t `A` 8001 ) )

    // ── local suspect, then timeout sweep → dead ─────────────────
    ( pb `suspect A: ` ( mtable_suspect t `A` 8001 ) )
    ( pst `A state: ` ( mtable_state_of t `A` 8001 ) )
    : ( Vec Member ) d ( mtable_sweep t )
    ( nurl_print `swept dead: ` ) ( nurl_println_int ( vec_len [Member] d ) )
    ( vec_free_with [Member] d \ Member mm → v { ( member_free mm ) } )
    ( pst `A state: ` ( mtable_state_of t `A` 8001 ) )

    // ── self-refutation: a Suspect-about-self bumps our incarnation ─
    ( apply_m t `self` 7000 0 @ MemberState { MSuspect } `refute self: ` )
    : Member sm ( mtable_self t )
    ( nurl_print `self inc: ` ) ( nurl_println_int . sm incarnation )
    ( member_free sm )

    // ── precedence: higher-inc Alive revives dead A ──────────────
    ( apply_m t `A` 8001 1 @ MemberState { MAlive } `revive A inc1: ` )
    ( pst `A state: ` ( mtable_state_of t `A` 8001 ) )

    // ── precedence: stale Suspect (inc0 < cur inc1) rejected ──────
    ( apply_m t `A` 8001 0 @ MemberState { MSuspect } `stale suspect A: ` )
    ( pst `A state: ` ( mtable_state_of t `A` 8001 ) )

    ( nurl_print `count: ` ) ( nurl_println_int ( mtable_count t ) )
    ( mtable_free t )
    ^ 0
}
