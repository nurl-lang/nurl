# pttvoice — Push-To-Talk voice over the NURL overlay

A small distributed voice app built on NURL's pubkey-addressed transport
(`stdlib/net/*`). It captures microphone audio, encodes it with **Opus**, and
pushes a talkspurt either to **one chosen peer** (unicast — peer-to-peer when the
transport can punch a direct path, relayed otherwise) or to **every member of a
group** (broadcast → relay multicast). A receiver decodes each frame and plays
it back. Audio is 48 kHz mono in 20 ms Opus frames.

> This folder is intentionally self-contained so it can later move to its own
> repository. It depends on the in-tree NURL stdlib (`stdlib/...`) and two system
> libraries, **libopus** and **ALSA (libasound)**, which `nurl.sh` auto-links when
> the FFI symbols appear and which `build.sh` detects (dropping the
> `stdlib/runtime.opus` / `stdlib/runtime.asound` sentinels).

## Files

| file | role |
|------|------|
| `opus.nu`  | libopus FFI + thin encode/decode wrappers; PCM helpers (signed-16 LE in a `Vec u`) |
| `audio.nu` | ALSA capture/playback; no-ops to silence when there is no sound device (headless) |
| `proto.nu` | the voice wire frame `['P''V'][type][seq:u32][opus…]` + decode |
| `ptt.nu`   | the app: relay dial, group join, capture→encode→send, recv→decode→play |
| `test_opus_roundtrip.nu` | offline: synth PCM → Opus encode → decode, checks a full energetic frame |
| `test_pipeline.nu`       | offline: PCM → Opus → proto frame → decode → Opus → PCM, seq + energy |

## Build & run

```sh
# from the repo root (build.sh must have been run once so the sentinels exist)
./nurl.sh pttvoice/ptt.nu

# 1) a relay (any reachable host)
./nurl.sh examples/relay.nu 127.0.0.1 47811

# 2) a listener
./pttvoice/ptt 127.0.0.1 47811 2 listen

# 3) a talker — broadcast a ~1 s talkspurt to the whole group
./pttvoice/ptt 127.0.0.1 47811 1 group

# …or unicast a talkspurt to node 2 (peer-to-peer if possible)
./pttvoice/ptt 127.0.0.1 47811 1 peer 2
```

```
./pttvoice/ptt <relay_host> <relay_port> <self_id> <mode> [target_id] [frames]
  mode = group | peer | listen
  frames = number of 20 ms frames to transmit (default 50 ≈ 1 s)
```

On a host with no sound card (CI, a headless server) capture yields a synth tone
and playback is a silent sink, so the network path still runs end to end — which
is how the live loopback above is verified without audio hardware.

## Offline tests (no relay, no audio)

```sh
./nurl.sh pttvoice/test_opus_roundtrip.nu && ./pttvoice/test_opus_roundtrip
./nurl.sh pttvoice/test_pipeline.nu       && ./pttvoice/test_pipeline
```

Both run leak-free under `NURL_SAN=1`.
