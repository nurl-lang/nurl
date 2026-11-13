### Fixed

- **A destructor that yields while a panic's drain runs it no longer corrupts the journal** (AGORA-623). A panic's drain kept its depth and its record of what it had freed per worker thread, while the journal it drains is the fiber's. A `% Drop` destructor that called `( yield )` during the drain parked its fiber: the fibers that ran next on that worker took the drain for their own and ended it, and a fiber resumed on another worker found no drain there. Under ASan + UBSan that was `passing zero to clz()` in the journal with one worker, a null `NurlPanicFrame` in `nurl_panic` and a double free in the drain with four. The drain now belongs to the fiber and moves with its journal at every switch. The drain loop reads no thread-local across a destructor's call, and `nurl_panic` jumps to the frame it read before the drain.

### Performance

- **A fiber switch moves less state** (AGORA-623). A context's recovery state is now two blocks, exchanged sixteen bytes at a time. The part that means something only under a `recover` frame (the journal, the slot stack, the frame chain, a drain's record) is skipped when neither side has a frame. A yield loop of two fibers on one worker is 12.9 % faster outside a recover extent and 4.5 % faster inside one (min of 21 runs, Tiger Lake). The per-fiber recovery slot grows from 14 to 16 words (+16 bytes per fiber).
