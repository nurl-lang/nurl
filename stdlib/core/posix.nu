// stdlib/core/posix.nu — pure-NURL POSIX syscall surface.
//
// FFI declarations for the libc syscalls used by process-spawn /
// proc-run, plus the constant + errno + waitpid-status helpers that
// runtime.c §2 exposes.
//
// Audience: stdlib modules that need raw POSIX semantics
// (`stdlib/std/process.nu`, future `stdlib/std/signal.nu`, parts of
// `stdlib/std/fs.nu`). User code is generally expected to use the
// higher-level wrappers — direct POSIX FFI is fine, but
// `process_run` / `file_open` / etc. are friendlier.
//
// Platform gating: every symbol below is POSIX-only. Win32 builds
// resolve them against winpthreads / msvcrt where applicable
// (read/write/close/getpid), and the rest return -1 via the
// `nurl_native_constant` thunk's WASI/Win32 path so NURL callers
// can detect "not available here" without crashing. The intended
// production callers will gate on a target check before using these.
//
// Memory model:
//
//   * Buffers passed to `read` / `write` are *u byte pointers from
//     the caller; the syscalls treat them as opaque bytes.
//   * `pipe` writes two fd ints into the caller-provided `*u`
//     buffer (sized via `nurl_native_sizeof "int"` × 2). The caller
//     owns that buffer.
//   * `execvp` consumes a `char *const argv[]` array — caller-owned;
//     execvp does NOT free it (on success it's irrelevant because the
//     process image is replaced; on failure caller cleans up).
//   * `fork` returns 0 in the child, positive pid in the parent, -1
//     on error. The child has its own address space copy; no shared
//     mutable state survives by default.
//   * `waitpid` writes the raw status int through a caller-provided
//     `*u`. Decode via `nurl_wait_is_exited` / `_exit_status` /
//     `_is_signaled` / `_term_sig`.

$ `stdlib/core/cell.nu`

// ── Native constants + errno ──────────────────────────────────────

// Look up a platform integer constant (O_NONBLOCK, F_GETFL, POLLIN,
// SIGTERM, …). Returns -1 for unknown names on every target, and -1
// for POSIX names on Win32 / WASI. See runtime.c §2 for the full list.
& `c` @ nurl_native_constant s name → i

@ posix_const s name → i { ^ ( nurl_native_constant name ) }

// Read / write the per-thread errno. NURL callers should snapshot it
// immediately after a -1-returning syscall — any intervening libc call
// may have clobbered it.
& `c` @ nurl_errno_get → i

& `c` @ nurl_errno_set i e → v

// Classify the current errno as one of the IoErr enum tags from
// `stdlib/core/errors.nu`. Replaces runtime.c's `nurl_errno_kind`
// (PURIFY 2026-05-24). Caller must read errno immediately after the
// failing syscall — any intervening libc call may clobber it.
//
//   0 = NotFound          (ENOENT)
//   1 = PermissionDenied  (EACCES, EPERM)
//   2 = AlreadyExists     (EEXIST)
//   3 = Interrupted       (EINTR)
//   4 = UnexpectedEof     (no errno mapping; reserved)
//   5 = WriteFailed       (no errno mapping; reserved)
//   6 = ReadFailed        (no errno mapping; reserved)
//   7 = Other
@ errno_kind → i {
    : i e ( nurl_errno_get )
    ? == e ( posix_const `ENOENT` ) { ^ 0 } {}
    ? == e ( posix_const `EACCES` ) { ^ 1 } {}
    ? == e ( posix_const `EPERM` ) { ^ 1 } {}
    ? == e ( posix_const `EEXIST` ) { ^ 2 } {}
    ? == e ( posix_const `EINTR` ) { ^ 3 } {}
    ^ 7
}

// ── waitpid status decoders ───────────────────────────────────────

// WIFEXITED / WEXITSTATUS / WIFSIGNALED / WTERMSIG are preprocessor
// macros in C; the runtime exposes them as plain functions because
// NURL has no preprocessor.
& `c` @ nurl_wait_is_exited i status → i  // 1 / 0
& `c` @ nurl_wait_exit_status i status → i  // exit code or -1
& `c` @ nurl_wait_is_signaled i status → i  // 1 / 0
& `c` @ nurl_wait_term_sig i status → i  // signal number or 0

// ── Process lifecycle ─────────────────────────────────────────────

// fork(2): returns 0 in child, child pid > 0 in parent, -1 on error.
// errno is set on -1.
& `c` @ fork → i

// execvp(3): replace the process image. Returns -1 (and sets errno)
// only on failure — on success it does not return.
& `c` @ execvp s file *u argv → i

// _exit(2): immediate process termination, no atexit handlers.
& `c` @ _exit i status → v

// waitpid(2): block (options = 0) or poll (options = WNOHANG) for a
// child. Writes the raw status through `*status_buf`. Returns child
// pid on success, 0 on WNOHANG-with-no-state-change, -1 on error.
& `c` @ waitpid i pid *u status_buf i options → i

// kill(2): send `sig` to `pid`. 0-signal probes for existence.
// Returns 0 on success, -1 with errno on failure.
& `c` @ kill i pid i sig → i

// getpid(2): current process id.
& `c` @ getpid → i

// ── File descriptor primitives ────────────────────────────────────

// pipe(2): writes the read end into `fds[0]` and the write end into
// `fds[1]` (int-sized slots in caller-owned buffer of >= 2 ints).
& `c` @ pipe *u fds → i

// dup2(2): duplicate `oldfd` onto `newfd`, closing `newfd` first if
// it was open. Returns `newfd` on success, -1 with errno on failure.
& `c` @ dup2 i oldfd i newfd → i

// close(2): release a file descriptor. Returns 0 / -1.
& `c` @ close i fd → i

// fcntl(2) — only the 3-arg integer form (used for F_GETFL/F_SETFL/
// F_GETFD/F_SETFD with O_NONBLOCK / FD_CLOEXEC). Returns int.
// fcntl(2) is `int fcntl(int, int, ...)` — VARIADIC in C, and the `...`
// marker is load-bearing rather than cosmetic. Apple's arm64 calling
// convention passes variadic arguments on the STACK, where x86-64 SysV
// and Linux AAPCS64 both pass them in the same registers as fixed ones.
// So a fixed-arity declaration works by accident on those two and hands
// the callee garbage on macOS arm64: `fcntl(fd, F_SETFD, FD_CLOEXEC)`
// put the flag in x2 while fcntl's va_arg read the stack.
//
// Nothing reported an error — F_SETFD simply set some other value. What
// it cost: process_spawn hung forever on macOS, because the exec-errno
// pipe's write end never became close-on-exec, so the child kept it open
// past execvp and the parent's read waited for an EOF that could not
// come. Sockets stayed blocking for the same reason (__set_nonblock is
// the same call), which stalled every async server on a worker thread.
& `c` @ fcntl i fd i cmd ... → i

// read(2) / write(2): bytes through `*u` buffer. Return count
// (positive), 0 (EOF on read), -1 with errno on error.
& `c` @ read i fd *u buf i n → i

& `c` @ write i fd *u buf i n → i

// Buffered binary read from stdin (NURL runtime `fread(stdin)`). Shares
// nurl_read_line's stdio buffer so framed stdio protocols (LSP/DAP) can
// read a header line with `read_line` (fgetc) then the body with
// `read_n_bytes` without a buffered-vs-raw split losing body bytes.
& `c` @ nurl_stdin_read *u buf i n → i

// ── File descriptor / mmap primitives ─────────────────────────────
//
// open(2): low-level fd-based file open. `flags` is `O_RDONLY` / etc.
// from `posix_const`; `mode` matters only when O_CREAT is set
// (typical caller passes 0). Returns the new fd or -1 with errno.
// open(2) is likewise `int open(const char *, int, ...)`; `mode` is the
// variadic argument. Same ABI reasoning as fcntl above.
& `c` @ open s path i32 flags ... → i32

// lseek(2): reposition the read/write head. `whence` is 0 (SET) /
// 1 (CUR) / 2 (END) — universal POSIX values. Returns the new
// offset on success (and so doubles as a "give me file size" tool
// when whence == SEEK_END), -1 on failure.
& `c` @ lseek i32 fd i offset i32 whence → i

// mmap(2): map `length` bytes of `fd` starting at `offset` into the
// caller's address space. `prot` is `PROT_READ` / etc.; `flags` is
// `MAP_PRIVATE` for a copy-on-write file mapping. Returns the
// mapping pointer or `MAP_FAILED` ((void*)-1) on failure.
& `c` @ mmap *u addr i length i32 prot i32 flags i32 fd i offset → *u

// munmap(2): release a previous mmap.
& `c` @ munmap *u addr i length → i32

// madvise(2): kernel hint for read-ahead pattern. Best-effort, no
// observable side effect on the data itself; ignore the return.
& `c` @ madvise *u addr i length i32 advice → i32

// ── Directory iteration ───────────────────────────────────────────
//
// opendir/readdir/closedir over libc's `DIR*` opaque handle. `readdir`
// returns a borrowed `struct dirent *` (libc-owned, invalidated by
// the next readdir on the same handle) — caller must copy the name
// before the next call. NURL accesses the `d_name` field through the
// `nurl_dirent_name` thunk in `runtime.c` because the offset varies
// per platform (Linux glibc = 19, macOS = 21) and porting that
// offset table into NURL buys nothing.

& `c` @ opendir s path → s

& `c` @ readdir s dirp → s

& `c` @ closedir s dirp → i32

& `c` @ nurl_dirent_name s de → s  // borrowed `de->d_name`

// ── Signal handling ───────────────────────────────────────────────

// signal(2) — returns the OLD handler (as opaque *u). Pass SIG_IGN /
// SIG_DFL (from posix_const) or a NURL closure's fn pointer. Caveat:
// signal(2)'s semantics are platform-tweaky; for robust handling use
// sigaction(2) once we expose it.
& `c` @ signal i signum *u handler → *u

// ── poll(2) ────────────────────────────────────────────────────────

// poll(2) — block until at least one fd in `fds` is ready, or
// timeout_ms elapses (-1 = wait forever, 0 = immediate poll).
// Returns number of fds with revents set, 0 on timeout, -1 on error.
// `fds` is a caller-owned `struct pollfd` array of `nfds` entries.
& `c` @ poll *u fds i nfds i timeout_ms → i

// ── struct pollfd helpers ──────────────────────────────────────────
//
// struct pollfd { int fd; short events; short revents; }
//
// Layout on every supported POSIX target: fd at offset 0 (4 bytes),
// events at offset 4 (2 bytes), revents at offset 6 (2 bytes). Total
// 8 bytes per entry. Helpers write/read those fields through a *u
// pointing at a contiguous pollfd-sized buffer (one entry or an
// indexed slot in a larger array).

// Bytes per pollfd entry, sized via nurl_native_sizeof so the value
// stays portable if a future Linux ABI grows the struct.
@ posix_pollfd_size → i { ^ ( nurl_native_sizeof `struct pollfd` ) }

// Write fd / events into the pollfd entry at byte offset `off`.
// Layout: { int fd @ 0, short events @ 4, short revents @ 6 } = 8 B.
// NURL has no pointer-resliceing — write each byte at `fds + off + N`
// directly. `. p i` on `*u` indexes a single byte slot.
@ posix_pollfd_set * u fds i off i fd i events → v {
    // fd is a 32-bit int at offset 0; emit four little-endian bytes.
    = . fds + off 0 # u & fd 255
    = . fds + off 1 # u & >> fd 8 255
    = . fds + off 2 # u & >> fd 16 255
    = . fds + off 3 # u & >> fd 24 255
    // events is a 16-bit short at offset 4 — two little-endian bytes.
    = . fds + off 4 # u & events 255
    = . fds + off 5 # u & >> events 8 255
    // zero the revents slot so a subsequent read sees a clean value.
    = . fds + off 6 # u 0
    = . fds + off 7 # u 0
}

// Read revents (short at offset 6) from the pollfd entry at byte
// offset `off`. Returns the 16-bit value as a non-negative i.
@ posix_pollfd_revents * u fds i off → i {
    : i lo & 255 # i . fds + off 6
    : i hi & 255 # i . fds + off 7
    ^ | lo << hi 8
}
