# `nurlbox` — the Swiss Army knife of NURL

One binary, many utilities. `nurlbox` is a busybox-shaped multi-call
executable: it decides which utility it is from the name it was invoked
under, so a directory of symlinks pointing at it is a complete userland.

```sh
nurlbox                     # list the applets
nurlbox cat file            # run one by name
ln -s nurlbox /usr/bin/cat  # …or install it as itself
cat file
```

Everything is pure NURL over the shipped standard library. There is no
shelling out, no `coreutils` underneath, and nothing to link beyond libc
— which is also why the same source builds for Linux, macOS, Windows and
wasm32-wasi, and **boots as its own kernel** on the unikernel target.

## The applets

| Group | Applets |
|---|---|
| text | `cat` `echo` `head` `tail` `wc` `seq` `yes` `tac` `rev` `nl` `cut` `tr` `sort` `uniq` `tee` |
| search & edit | `grep` `egrep` `fgrep` `sed` `find` |
| files | `ls` `stat` `du` `cp` `mv` `rm` `mkdir` `rmdir` `ln` `touch` `chmod` `readlink` `realpath` `truncate` `mktemp` |
| digests | `md5sum` `sha1sum` `sha256sum` `sha512sum` `cksum` `crc32` `base64` |
| shell | `test` `[` `expr` `xargs` `sleep` `usleep` `true` `false` `env` `printenv` `printf` `which` |
| system | `pwd` `basename` `dirname` `uname` `arch` `hostname` `whoami` `id` `groups` `logname` `nproc` `date` `sync` `clear` `tty` |

## What "clone" means here

The specification is the original, and the test suite says so: every case
in [`tests/cases.sh`](tests/cases.sh) runs the same command line through
`nurlbox` and through the system `busybox`, and the two must agree on
stdout, on the bytes, and on the exit status. Where an applet mutates the
filesystem the comparison is the resulting *tree* — names, contents and
permission bits — because that is a `cp`'s real output, not what it
printed.

```sh
./tests/nurlbox_test.sh          # ~260 differential cases
BUSYBOX=/path/to/busybox ./tests/nurlbox_test.sh
```

Three deliberate divergences, each because the original takes a shortcut
a modern tool should not:

- **Byte fidelity.** A file whose last line has no newline does not grow
  one, in any applet. busybox's `cat -n` and `sed` both append one.
- **CRLF survives.** `head`, `cat`, `sed` and the rest copy the line
  terminator the input carried, rather than normalising it to `\n`.
- **No trailing whitespace.** `ls -lh` prints `total 12K`, not
  `total 12K····`.

Where busybox does not implement an option at all (`cat -E`, `cat -s`,
`nl -n`, `cksum`), the reference is GNU coreutils, and the suite compares
against that instead. And `find` sorts each directory it reads, so a run
is reproducible; the original emits in whatever order the filesystem
answered.

## What it needed from the language

The point of writing a userland is that it finds the holes. These were
fixed where they actually were, not worked around here:

| Gap | Fix |
|---|---|
| No `stat(2)` at all | `FileStat` + `fs_stat` / `fs_lstat` / `fs_fstat`, mode strings, `fs_set_times`, `fs_user_name` — `stdlib/std/fs.nu` over a new fixed-layout runtime thunk |
| No way to enumerate the environment | `env_count` / `env_entry` / `env_list` — `stdlib/ext/env.nu` |
| No `uname`, host name or processor count | `stdlib/std/sysinfo.nu` |
| Time was UTC-only | `tz_offset` / `tz_name` / `time_local` — `stdlib/std/time.nu`, plus a dozen more `strftime` directives |
| `bufio` could not read a line verbatim | `bufreader_read_line_raw`, which keeps the terminator |
| Regular expressions had no capture groups | a Pike VM with capture slots in `stdlib/ext/regex.nu`; `regex_find_caps`, `regex_ngroups`, `regex_expand` |
| The wildcard matcher was private to `fs_glob` | `fs_match` / `fs_match_glob` |
| `path_dirname "foo"` answered `""`, `path_basename "/a/b/"` answered `""` | POSIX semantics in `stdlib/std/path.nu` |
| `file_delete` could not delete a dangling symlink | it stopped probing with `access(2)` first |
| `mkdir` ignored the umask | `nurl_dir_create` passes 0777 and lets the kernel subtract |

## Memory

Leak-clean under AddressSanitizer with `detect_leaks=1` across every
applet — the manual-handle contract (`String`, `Vec`) is honoured on
every path, including the error paths.
