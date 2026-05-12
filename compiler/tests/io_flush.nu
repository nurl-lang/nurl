// I/O Tier 0 completion — verifies flush + read_line linkage.
//
// read_line is placed in an untaken branch so the test does not block
// on stdin; we only need to confirm that the runtime symbol resolves
// at link time and that the compiler's auto-drop treats the returned
// string as owned (no compile-time error about unreferenced owners).

$ `stdlib/core/io.nu`

@ main → i {
  : ~ b never F

  ? never {
    : String line ( read_line )
    ( nurl_print ( string_data line ) )
  } {}

  ( nurl_print `before flush\n` )
  ( flush )
  ( nurl_print `before eflush\n` )
  ( eflush )

  : b eof ( stdin_eof )
  ? eof { ( nurl_print `eof=T\n` ) } { ( nurl_print `eof=F\n` ) }

  ( nurl_print `done\n` )
  ^ 0
}
