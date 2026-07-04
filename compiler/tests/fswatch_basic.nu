// fswatch_basic.nu — std/fswatch.nu B8 (Linux inotify watching).
//
// Creates a unique temp dir, watches it with FSW_ALL, then drives
// deterministic same-process filesystem traffic: one write_file emits
// IN_CREATE → IN_MODIFY → IN_CLOSE_WRITE in queue order, a delete
// emits IN_DELETE. Each event is popped with the blocking
// fswatch_next and printed as a stable `label: name` line. Cleans up
// (rm watch, close watcher, remove tree) so the suite stays ASan-clean.

$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/fswatch.nu`

@ ev_label i mask → s {
    ? != & mask FSW_CREATE 0 { ^ `create` } {}
    ? != & mask FSW_MODIFY 0 { ^ `modify` } {}
    ? != & mask FSW_CLOSE_WRITE 0 { ^ `close_write` } {}
    ? != & mask FSW_DELETE 0 { ^ `delete` } {}
    ? != & mask FSW_MOVED_FROM 0 { ^ `moved_from` } {}
    ? != & mask FSW_MOVED_TO 0 { ^ `moved_to` } {}
    ^ `other`
}

// Pop one event and print `label: name` (path-stable, golden-safe).
@ show_next FsWatch w → v {
    : !FsWatchEvent FsWatchErr r ( fswatch_next w )
    ?? r {
        T e → {
            ( nurl_print ( ev_label . e mask ) )
            ( nurl_print `: ` )
            ( nurl_print ( string_data . e name ) )
            ( nurl_print `\n` )
            ( string_free . e name )
        }
        F err → {
            ( nurl_print `next FAILED: ` )
            ( nurl_print ( fswatch_err_name err ) )
            ( nurl_print `\n` )
        }
    }
}

@ main → i {
    // unique, self-cleaned root (getpid keeps it collision-free
    // without leaking the pid into the golden)
    : String rootstr ( string_with_cap 48 )
    ( string_push_str rootstr `/tmp/nurlfsw_root_` )
    ( string_push_str rootstr ( nurl_str_int ( getpid ) ) )
    : s root ( string_data rootstr )
    : !v IoErr _rm0 ( dir_remove_all root )  // clear any stale tree
    ?? _rm0 { T _ → {} F _ → {} }
    : !v IoErr _mk ( dir_create root )
    ?? _mk { T _ → {} F _ → ( nurl_print `mkdir root FAILED\n` ) }

    : !FsWatch FsWatchErr wr ( fswatch_new )
    ?? wr {
        T w → {
            : ~ i wd 0
            : !i FsWatchErr ar ( fswatch_add w root FSW_ALL )
            ?? ar { T d → = wd d F _ → ( nurl_print `add FAILED\n` ) }

            // write_file = create + write + close ⇒ three queued events
            : String f ( __glob_join root `f.txt` )
            : !v IoErr _w ( write_file ( string_data f ) `hello` )
            ?? _w { T _ → {} F _ → ( nurl_print `write FAILED\n` ) }
            ( show_next w )  // create: f.txt
            ( show_next w )  // modify: f.txt
            ( show_next w )  // close_write: f.txt

            : !v IoErr _d ( file_delete ( string_data f ) )
            ?? _d { T _ → {} F _ → ( nurl_print `delete FAILED\n` ) }
            ( show_next w )  // delete: f.txt
            ( string_free f )

            : !i FsWatchErr rr ( fswatch_rm w wd )
            ( nurl_print `rm_ok=` )
            ?? rr { T _ → ( nurl_print `T` ) F _ → ( nurl_print `F` ) }
            ( nurl_print `\n` )
            ( fswatch_close w )
        }
        F err → {
            ( nurl_print `new FAILED: ` )
            ( nurl_print ( fswatch_err_name err ) )
            ( nurl_print `\n` )
        }
    }

    : !v IoErr _rm ( dir_remove_all root )
    ?? _rm { T _ → {} F _ → {} }
    ( string_free rootstr )
    ^ 0
}
