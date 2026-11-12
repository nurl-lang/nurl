// diag_sync_dyn_impl_breaks_promise.nu — `% Look [T] : Send Sync`
// promises that one `%Look` object may be reached from two threads at
// once, so every type implementing `Look` is held to Sync where its impl
// is. `Buf` reaches a Cell, whose writes are unsynchronised: the impl is
// rejected at its `%`, naming the Cell (the Send half of the promise
// holds — a Cell may move). (The library's Cell, imported: a type named
// `Cell` the file does not declare is no Cell — agora #714.)
$ `stdlib/core/cell.nu`

: Buf { Cell c }

% Look [T] : Send Sync { @ look T self → i }

% Look Buf { @ look Buf b → i { ^ 0 } }

@ main → i { ^ 0 }
