### Added

- **`pfile_try_lock`: a file's exclusive lock, taken without waiting**
  (std/pfile.nu). It answers T when the handle now holds the lock, and F
  when another holder has it. The lock belongs to the open descriptor
  (flock(2); LockFileEx on Windows). It goes when the last copy of the
  handle does, and the kernel lets go of it when the process dies, killed
  or not, so a crash leaves no stale lock behind. Two opens of one file
  are two holders, inside one process too. On the unikernel the guest is
  the only program, and every lock is granted. nurldb locks its database
  directory with it, so a second open is refused instead of writing the
  same files.
