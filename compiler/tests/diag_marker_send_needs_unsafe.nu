// diag_marker_send_needs_unsafe.nu
// `% Sync T { }` stops the derivation at T: nothing inside is examined.
// Written by safe code over a Cell, it is a data race the compiler can no
// longer see — two threads writing one buffer through an Arc. Outside the
// standard library a positive marker is an unchecked promise, so it is
// spelled `unsafe % Sync T { }`, as an unchecked body is `unsafe @`.
// (A `% NotSend` / `% NotSync` / `% Frozen` only adds checks: no `unsafe`.)

$ `stdlib/core/cell.nu`
$ `stdlib/core/marker.nu`

: Scratch { Cell c }

% NotSend Scratch {}

% Frozen Scratch {}

: Shared2 { Cell c }

% Sync Shared2 {}

@ main → i { ^ 0 }
