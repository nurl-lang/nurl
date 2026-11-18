### Performance

- **Self-compile is 8M instructions faster** (−0.03%, callgrind, ASLR off). AGORA-813 added a check, run at every call, of whether a callee not yet compiled returns a closure: it looked up the callee's return type and parsed it each time. A library function compiled lazily was parsed again at each of its calls. The verdict "returns no closure" is now remembered per callee: its declared type does not change. Generated code is byte-identical.
