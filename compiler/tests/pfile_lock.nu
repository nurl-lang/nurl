// pfile_lock.nu — std/pfile.nu's pfile_try_lock.
//
// The lock belongs to an open handle, so two opens of one file inside one
// process are two holders: the first takes the lock, the second is told
// another holder has it (without waiting), and once every copy of the
// first handle is gone (its descriptor closed) the second takes the lock.
// A second file is a lock of its own.
// requires: live

$ `stdlib/core/string.nu`
$ `stdlib/std/fs.nu`
$ `stdlib/std/pfile.nu`
$ `stdlib/ext/env.nu`

@ tmp_path s name → String {
    : String p ( env_temp_dir )
    ( string_push_char p 47 )
    ( string_push_str p name )
    ^ p
}

@ verdict s label ! b IoErr r → v {
    ( nurl_print label )
    ?? r {
        T got → ( nurl_println ? got `held by this handle` `held by another` )
        F _ → ( nurl_println `error` )
    }
}

@ main → i {
    : String tp ( tmp_path `nurl_pfile_lock.lock` )
    : s path ( string_data tp )
    : String tq ( tmp_path `nurl_pfile_lock_other.lock` )
    : s other ( string_data tq )
    {
        : PFile second ?? ( pfile_open path PFILE_CREATE ) { T h → h F _ → { ( nurl_println `open failed` ) ^ 1 } }
        {
            : PFile first ?? ( pfile_open path PFILE_CREATE ) { T h → h F _ → { ( nurl_println `open failed` ) ^ 1 } }
            : PFile copy ( PFile_share first )
            ( verdict `first:         ` ( pfile_try_lock first ) )
            ( verdict `second:        ` ( pfile_try_lock second ) )
            : PFile o ?? ( pfile_open other PFILE_CREATE ) { T h → h F _ → { ( nurl_println `open failed` ) ^ 1 } }
            ( verdict `another file:  ` ( pfile_try_lock o ) )
        }
        ( verdict `second, after: ` ( pfile_try_lock second ) )
    }
    ( file_delete path )
    ( file_delete other )
    ^ 0
}
