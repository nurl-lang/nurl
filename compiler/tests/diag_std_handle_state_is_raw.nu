// A std handle that writes keeps its state in an rcbox, and what an rcbox
// holds is reached by address only: checked code cannot read a DosState's
// counters around the lock its functions take.

$ `stdlib/std/dos.nu`
$ `stdlib/core/vec.nu`

@ main → i {
    : DosState g ( dos_state_new 4 2 )
    : *DosImpl d ( shared_ptr [DosImpl] . g ctl )
    ^ ( vec_len [i] . d counts )
}
