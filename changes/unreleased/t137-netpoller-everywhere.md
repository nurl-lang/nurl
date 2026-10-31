### Changed

- **Breaking (Windows): async socket I/O needs Windows build 20348 or
  later — Windows 11 or Windows Server 2022** (Agora #137). A fiber's
  socket wait now runs on the netpoller, which on Windows is an I/O
  completion port fed by `ProcessSocketNotifications`, a call Windows 10
  does not have. Every program still starts on Windows 10, and fibers,
  timers, sleeps, channels and blocking socket I/O work there; the first
  socket wait from a fiber panics with a message that names the
  requirement and what still works.

### Performance

- **The netpoller runs on Windows, macOS and FreeBSD, not only Linux**
  (Agora #137). Those hosts ran a dedicated `poll(2)`/`WSAPoll` reactor
  thread, and a ready socket waited until the OS gave that one thread a
  time slice: under load an accept came 1 820 dispatches late on the
  Windows CI runner, 4 070 on the FreeBSD CI VM, and 88 to 1 673 on a
  16-thread Windows laptop running 16 CPU hogs, where the bound is 16.
  Now, as on Linux, an idle worker blocks in the kernel's readiness queue
  and a busy one drains it every 16th dispatch: kqueue (`EV_CLEAR` +
  `EVFILT_USER`) on macOS and FreeBSD, a completion port with persistent
  edge-triggered `ProcessSocketNotifications` registrations on Windows.
  On that laptop `sched_accept_admission`'s worst delay is 16 idle and
  16 under the same load, and the test runs on Windows, macOS and FreeBSD
  instead of being skipped. A park no longer costs a wake-socket send,
  an O(waiters) `WSAPoll` rebuild and a cross-thread wake; a socket is
  registered once per lifetime.
