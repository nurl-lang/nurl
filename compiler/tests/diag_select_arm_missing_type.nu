// diag_select_arm_missing_type.nu — a select channel arm without its
// '[T]' element type.
//
// The default-arm branch tested only "is this an identifier", so a
// channel arm's name was accepted AS the '_' marker and the parse then
// failed one token later with "expected '{' to open the default arm's
// body" — a message about a construct the writer had not used, naming a
// cure ('_ → { body }') that has nothing to do with the mistake. The
// marker must literally be '_'; anything else is a channel arm that
// lost its brackets, and the arm-shape message says so.
$ `stdlib/std/channel.nu`

@ main → i {
    : ( Channel i ) ints ( chan_new [i] )
    ?? { ints → oi { ^ 0 } }
    ^ 0
}
