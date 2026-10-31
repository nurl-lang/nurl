### Fixed

- **A fiber that waits on a `Cond` parks instead of stopping its worker
  thread** (Agora #255). `std/thread.nu`'s `Cond` was a raw
  `pthread_cond_t`, so every wait on one from a fiber — a `Locked` whose
  value another fiber had checked out (`locked_take`), `sem_acquire`,
  `locked_await`, nurldb's WAL flush wait — put the whole worker thread
  to sleep. Two fibers sharing a `Locked` on one worker deadlocked as
  soon as the one holding the value parked on I/O; with more workers each
  waiter pinned one (4 fibers on a shared psql connection ran at half the
  throughput of 1). The `Cond` is now the runtime's: a `pthread_cond_t`
  for threads plus a FIFO of parked fibers under a lock of its own, woken
  with the runtime's race-safe timed park, so a waker need not hold the
  caller's mutex. Fibers and threads may wait on one `Cond`, as they
  already could on the unikernel. The common signal with no fiber waiting
  costs one atomic load more; a thread ping-pong over channels and a
  4-thread `Locked` counter measured the same before and after.
