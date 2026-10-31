### Added

- **`nurlpkg test --sim [--seeds N|A..B] [--seed S]`: the same tests under
  many schedules, and any failing one replayed exactly** (Agora #261, DST
  3/4). Each test is built once as a deterministic simulation (the new
  `nurl --sim`, on the cooperative runtime with a virtual clock, seeded
  entropy and a seeded schedule) and run once per seed. A test passes
  when every seed does; a failing one prints how many seeds it passed,
  the first seed it failed under, and the line that replays that run byte
  for byte (`nurlpkg test --sim --seed S tests/x.nu`). `netsim_new` with
  seed 0 takes the run's seed, so a simulated network varies with the
  sweep. On the gate's fixture a read–yield–write race on a shared counter
  fails under 25 of 40 seeds and its replay fails 10 times out of 10,
  identically, while the atomic version passes all 40; the 40-seed sweep
  of both takes 20 seconds.
