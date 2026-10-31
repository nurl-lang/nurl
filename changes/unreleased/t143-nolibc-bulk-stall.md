### Fixed

- **A bulk send over the no-libc socket layer runs at the speed of its
  bytes, not of a timer** (Agora #143). Without a libc (the unikernel,
  and `unikernel/run_nolibc_tests.sh` on Linux) the TCP is the NURL
  socket layer, `unikernel/net/sockets.nu`, and both ends of a loopback
  connection run as coroutines on one thread. A socket wait drove the
  stack once, and then blocked, with the frames that drive had just
  queued still undelivered: the ACK a segment is owed, the data a window
  update releases. Nothing else delivers them, so the scheduler slept
  until the sender's retransmit deadline. Every RTT sample held that
  sleep, so the deadline grew 1.6× a window. `net_sendfile` took 26–33 s
  instead of 0.25 s, and hit the corpus runner's 60 s limit once under CI
  load. A wait now blocks only once its own drives leave no frame queued.
  The new corpus test `net_bulk_no_stall` streams 1 MB from a server
  thread to the main thread and bounds the time: 19 ms with no libc,
  11 ms hosted.
