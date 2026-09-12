// diag_default_on_sink.nu — a default value on a 'sink' parameter.
//
// A 'sink' parameter CONSUMES its argument. A default is spliced into
// every call that omits it, so the same value would be consumed once per
// call — an ownership claim the declaration cannot make good on.
@ take i n sink s label = `none` → i { ^ n }

@ main → i {
    ^ ( take 1 )
}
