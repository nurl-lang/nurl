// A bare `^` (no value) is only legal in a `→ v` function. In a
// value-returning function it must be rejected, not silently return junk.
@ f i x → i { ? > x 0 { ^ } {} ^ 0 }

@ main → i { ^ ( f 5 ) }
