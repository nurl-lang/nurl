### Fixed

- **The ownership engine (`--engine`) releases a then-only arm's discarded temporary** (AGORA-869, agora #766). `? c { ( mk r ) } {}` releases the arm's value where the arm ends, and runs its `% Drop`. A drop that clears a shared payload under another handle's view is refused now, as in nurlc. A binding named as the tail, `? c { hs } {}`, is only lent to the arm and is not released. An ordinary compile is unchanged.
