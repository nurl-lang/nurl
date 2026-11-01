# Filesystem publication

Import `stdlib/std/fs.nu` for filesystem operations returning `! T IoErr`.

`fs_tempdir(dir, prefix)` exclusively creates a uniquely named directory and
returns its owned `String` path. An empty `dir` means the current directory.
POSIX directories start with mode `0700`; Windows inherits the parent directory's
ACL. Creation uses the directory operation itself, with no intervening unlink.
WASI creation remains subject to preopened directory capabilities. The nolibc
provider uses the platform entropy and directory operations; a guest with no
writable filesystem reports its filesystem error. The caller removes the directory with
`dir_remove_all`; the path is dropped with its binding.

For scratch space, put it under the platform's temp directory:
`env_temp_dir()` from `stdlib/ext/env.nu`. On POSIX that is `$TMPDIR` when
set and non-empty, else `/tmp`. On Windows it is what `GetTempPathW` answers:
`%TMP%`, else `%TEMP%`, else `%USERPROFILE%`, else the Windows directory.
`TMPDIR` is not read on Windows, because Git Bash exports it as a POSIX path
that a native program cannot open. The result is never empty and has no
trailing separator.

```nurl
$ `stdlib/std/fs.nu`
$ `stdlib/ext/env.nu`
$ `stdlib/core/string.nu`

@ main → i {
    : String root ( env_temp_dir )
    ?? ( fs_tempdir ( string_data root ) `myapp-` ) {
        T dir → {
            // … work in dir …
            ?? ( dir_remove_all ( string_data dir ) ) { T _ → {} F _ → {} }
        }
        F _ → { ^ 1 }
    }
    ^ 0
}
```

`fs_tempfile(dir, prefix)` similarly creates an empty, uniquely named file.
To replace a working file or executable, create this temporary file in the
**destination directory**, copy the new contents into it, apply any permissions,
and call `fs_rename(staged, destination)` only after those operations succeed.
Delete the staged file after any failure. Both POSIX and Windows replacement
keep the prior destination in place if replacement fails. Cross-filesystem
moves and Windows sharing restrictions return an error.

`fs_copy_file(source, destination)` copies in 64 KiB chunks and truncates the
specified destination. It reports source read errors and buffered write errors,
including errors discovered when closing either stream. It does not preserve
permissions or modification times. Use a staged destination when a partial
copy must not replace a working file.

Atomic visibility and crash durability are separate guarantees. Applications
that require persistence across a system crash must also use the file and
directory synchronization primitives appropriate to their storage protocol.

The `fs_atomic` compiler test covers directory uniqueness and permissions,
replacement and failure preservation, read failures, and buffered write failure
on hosts providing `/dev/full`. The package tool publication controls also
pause a real copy while the previous executable is running and inject permission
and rename failures.
