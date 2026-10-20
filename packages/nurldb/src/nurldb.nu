// packages/nurldb/src/nurldb.nu — the library: a relational database in
// pure NURL.
//
//   $ `deps/nurldb/src/nurldb.nu`
//
//   : Db d ?? ( db_open `/var/lib/app/db` ( db_default_opts ) ) { T x → x F e → … }
//   : ~ Session s ( session_new d )
//   ?? ( session_exec s ( string_from `SELECT name FROM emp WHERE id = 3` ) ) {
//       T r → ( nurl_print ( string_data ( result_text r ) ) )
//       F e → ( nurl_println ( string_data e ) )
//   }
//   ( session_close s )
//   ( db_close d )
//
// A Db is shared by every thread that uses it (each with a Session of its
// own); `serve` puts it on a TCP port. See README.md for the SQL it
// speaks and how it is built.

$ `exec.nu`
$ `server.nu`
