### Fixed

- **The ownership engine (`--engine`) refuses views sent to another thread through a wrapper** (AGORA-869, AGORA-812). `@ sendit ( Channel ( Vec s ) ) ch ( Vec s ) xs → v { ( chan_send [( Vec s )] ch xs ) }` stores what its parameter holds into the channel, a store the engine summarises as `LK_HELD`. The thread rule asked only a store of the value itself or of its handle, so a Vec of views of a local sent through `sendit`, or through two such wrappers, was accepted. It is refused now, as in nurlc. An ordinary compile is unchanged.
