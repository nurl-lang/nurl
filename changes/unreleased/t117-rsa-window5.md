### Performance

- **RSA-2048 signing is 8 % faster on CPUs without AVX-512 IFMA**
  (Agora #117). The constant-time exponentiation of each CRT half uses
  fixed 5-bit windows instead of 4-bit ones. A blinded 1088-bit half
  exponent takes 218 window multiplies and 30 table ones instead of 272
  and 14. The entry is still chosen by a masked scan of the whole table,
  now 32 entries, done on v256 lanes in an x86-64-v3 clone
  (`__rm_sel32`). That costs less than the scalar scan of sixteen did.
  The table's even powers are squarings. On a Sapphire Rapids class Xeon
  with `NURL_CPU_IFMA=0` (the ADX tier, what Zen 3 runs), best of seven
  min-of-seven runs: 792 → 729 µs, against aws-lc's 696 µs with IFMA
  masked. The table is 4 KB a half during a signature instead of 2 KB.
  The IFMA tier is unchanged.
