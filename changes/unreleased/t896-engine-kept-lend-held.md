### Changed

- **The ownership engine checks what a kept lend holds** (AGORA-896). A value the compiler hands over as it is (a kept lend, no copy made) used to skip every check after the copy decision. It now still has what it holds checked, as the reference checker in tools/ncore has since github#1925. No program's verdict changes.
