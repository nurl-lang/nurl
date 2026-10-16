# whisper

Speech recognition in pure NURL: real audio in, real text out. Runs
OpenAI's whisper models from the checkpoints they are actually
distributed in — Hugging Face safetensors or whisper.cpp's `ggml-*.bin`
— on the GPU (CUDA) or the CPU (OpenMP), with identical output on both.

```
nurlpkg install whisper
```

```
$ whisper transcribe ggml-large-v3.bin meeting.wav --vad --timestamps
[00:59.85 --> 01:07.49] And so, my fellow Americans, ask not what your country can do for you.
[01:08.21 --> 01:10.39] Ask what you can do for your country.
```

Output is verified word-for-word against Hugging Face `transformers` on
the same model. Nothing is hardcoded to a model size: mel bands, widths,
layer and head counts are read from the checkpoint itself, so everything
from `tiny` to `large-v3` works with the same binary.

## Getting a model

Two formats are supported. Both download sources below have been stable
for years and are the canonical homes of these files:

**whisper.cpp ggml — one self-contained file** (hyperparameters,
vocabulary and weights together; the easiest to move around):

> https://huggingface.co/ggerganov/whisper.cpp

```
curl -LO https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3.bin
whisper transcribe ggml-large-v3.bin clip.wav
```

Any of `ggml-tiny.bin` … `ggml-large-v3.bin` / `ggml-large-v3-turbo.bin`
works. The quantised variants (`q5_0`, `q8_0`) are refused with a clear
message for now — use the f16 files.

**Hugging Face checkpoint — a directory** with `config.json`,
`model.safetensors` and `tokenizer.json` side by side:

> https://huggingface.co/openai/whisper-large-v3
> https://huggingface.co/openai/whisper-tiny — likewise `-base`, `-small`, `-medium`
> https://huggingface.co/distil-whisper/distil-large-v3 — English-only, about twice as fast

```
mkdir large-v3 && cd large-v3
for f in config.json model.safetensors tokenizer.json; do
  curl -LO https://huggingface.co/openai/whisper-large-v3/resolve/main/$f
done
cd .. && whisper transcribe large-v3 clip.wav
```

The same weights in either container produce the same transcript.

## Transcribing

```
whisper transcribe <model> <audio.wav> [options]
```

| option | effect |
|---|---|
| `--lang CODE` | language, lowercase two-letter (`en`, `fi`, `sv`, …; default `en`). Uppercase input is normalized; an unknown code reports itself. |
| `--vad` | skip non-speech before the model sees it (adaptive-floor energy detector). Faster on sparse audio, and rescues speech that straddles a 30 s window boundary. |
| `--timestamps` | emit `[a --> b] text` segments using whisper's own timestamp tokens, under OpenAI's constrained-decoding rules. With `--vad`, times are mapped back to the recording's real clock. |
| `--nospeech P` | drop a window when the model itself is ≥ P sure it holds no speech (default 0.6; 1 disables). This is what keeps "Thank you." out of the silences. |
| `--max N` | stop after N tokens per window (default 200) |

WAV input at any sample rate and bit depth is resampled to 16 kHz mono
internally (windowed-sinc, not linear interpolation).

## Serving

```
$ whisper serve ggml-large-v3.bin --addr 0.0.0.0:6543 --tls --lang fi
whisper: self-signed TLS minted — the browser will warn once; accept it and the microphone works
whisper serving on https://0.0.0.0:6543 (test page at /, POST /inference, GET /health, WS: stream audio)
```

The model loads once, before the port opens; a request pays only for its
own audio (distil-large-v3: 0.33 s per warm request, where a cold CLI
invocation of the same clip costs 1.15 s).

**`--unload-after SECONDS`** makes the model a thing the server *holds*
rather than *is*: after that many idle seconds — no request, no open
stream — the model is closed (device buffers, kernels, the CUDA context)
and the next request reloads it before it runs. While idle the server is
the port and about 60 MB of process; large-v3 gives back 4.8 GB of device
memory. The reload is what a fresh start costs minus the process: on an
RTX 4090 with the file in the page cache, large-v3 (3.1 GB) reloads in
~0.73 s and turbo (1.6 GB) in ~0.47 s, so the first request after a sleep
answers in 1.3 s / 0.8 s where a warm one takes 0.54 s / 0.33 s. `0`
(the default) keeps the model for the process's life. `/health` says which
state it is in (`status` `ok` or `idle`, plus `loads`, `unloads`,
`last_load_ms`, `idle_s`); a client should treat `idle` as healthy.

Loading is the file's own copy bandwidth and nothing else: the container
is mmap'd (no read into memory, no 3 GB host copy kept for the model's
life — the resident server's RSS is ~130 MB where 1.1.x held 3.2 GB),
every tensor is carved from 128 MB device arenas rather than allocated
one by one, and the bytes go up as one streamed batch through pinned
staging (`gk_upload_batch` in packages/gpukit). A cold start went from
2.35 s to 0.8 s on large-v3.

**`GET /`** is a built-in test page: drop an audio file on it, or press
*Start microphone* and watch utterances appear as you pause — or pick
*drafts* and watch them form word by word, with the room's noise level
and the learned pause underneath. The page is staged by `nurlpkg install`
into `share/whisper/` next to the binary, with the VAD weights.

**`POST /inference`** is whisper.cpp's server surface, so its clients
work unchanged: multipart `file` field, optional `language` and
`response_format` (`json`|`text`) fields. A raw WAV body also works, and
per-request `vad=true` / `timestamps=true` fields override the server
flags.

**WebSocket, same port** — live audio in, utterances out:

```
→ {"format":"pcm16","lang":"fi"}                    (optional config, any time)
← {"status":"ok","format":"pcm16","vad":"silero","pause_ms":400,…}
→ <binary frames: raw PCM16 @ 16 kHz>
← {"type":"final","seg":1,"text":" Kaksikymmentäneljä.","t0":1.27,"t1":2.73,
   "speech_t0":1.66,"speech_t1":2.53,"proc_ms":0}
← {"error":"…"}                                     (failures are named, never silent)
```

`t0`/`t1` are seconds on the stream's clock (the audio that was
transcribed, lead-in included); `speech_t0`/`speech_t1` where the voice
itself began and ended — what a game compares with its deadline. A client
that sends no configuration gets what it always got, plus the new fields.

What cuts the stream into utterances, every 32 ms:

* **Silero VAD v5**, in NURL on the CPU (`src/silero.nu`, 0.4 ms per
  32 ms chunk; checked against onnxruntime on the original ONNX file to
  5·10⁻⁶). It hears a voice, not loudness: a fan, music, a keyboard or the
  game's own sound effects do not hold an utterance open. The weights
  (MIT, `vad/`) are installed beside the binary; `--vad-model FILE` points
  elsewhere, `--energy` (or no weights) falls back to an energy detector.
* **The room, measured continuously**: the noise floor (20th percentile of
  the last 10 s of non-speech), the speaker's own level (90th percentile of
  the last 20 s of voice) and how readily Silero fires on this room's noise
  — its thresholds rise above that.
* **A near-field gate**: a voice more than 10 dB (`near_db`) below the
  speaker's own is someone else — a television, a sibling across the room
  — and neither starts an utterance nor keeps one open.
* **A closing pause learned from the speaker**: the gaps between their
  words are measured as they talk, and the silence that ends an utterance
  is 1.3 × their 90th percentile + 150 ms (300…1000 ms, starting at 400). A
  close followed quickly by more speech counts as a gap, so a speaker who
  keeps getting cut mid-sentence stops being cut.
* **The answer is ready when the pause closes**: as soon as the speaker
  goes quiet, the utterance is transcribed with the full context while the
  pause runs; if nothing more is said it is the final (`proc_ms` 0). The
  log-mel is computed only where the audio is (a 2 s answer: ~10 ms
  instead of ~110), and each utterance is still gated by the model's own
  no-speech probability.

The configuration message takes any subset of:

| field | |
|---|---|
| `format` | `pcm16` (default) or `float32` |
| `lang` | the language (default: `--lang`) |
| `partials` | `true`: drafts while the utterance is spoken — `{"type":"partial","seg","text","stable","t0","t1","pause_ms"}`. `stable` is the prefix two drafts in a row agreed on; every utterance that had drafts ends in a final, an empty one included |
| `partial_ms` | a draft per this much new speech (default 300) |
| `pause_ms` | a fixed closing pause (turns the learning off unless `adaptive:true` comes with it) |
| `adaptive`, `min_pause_ms`, `max_pause_ms` | the learned pause and its range |
| `threshold` | Silero's p(speech) that opens an utterance (default 0.5) |
| `near_db` | the near-field gate (default 10; 0 = off) |
| `max_utt_ms` | close at the best gap past this (≤ 28000, whisper's window is 30 s) |
| `events` | `{"type":"start","seg","t0"}` when speech begins |
| `levels` | `{"type":"level","noise_db","speech_db","snr_db","p_noise","pause_ms","threshold"}` once a second |
| `vad` | `silero` or `energy` |

and two commands: `{"cmd":"end"}` (the utterance is over — transcribe it
now) and `{"cmd":"reset"}` (forget the open utterance, e.g. when a new
question appears).

Drafts run the encoder over the audio plus 5 s (at least 10 s) instead of
30 s — whisper.cpp's `audio_ctx` — which matched the full-context text on
every test clip and costs about half. They are drafts: mid-word a draft
can say "48." for "neljäkymmentä|kaksi", so act on `stable` or on the
final, not on the newest draft.

Measured in real time over the WebSocket (large-v3, RTX 4090; eight spoken
answers, time from the end of speech to the final):

| room | 3.3.0 | 3.4.0, `pause_ms:300` |
|---|---|---|
| quiet | ~930 ms | 73–306 ms |
| a television talking 12 dB below the player | 1–6.7 s, the TV's sentence came back as an answer | 185–406 ms, every answer right |
| music 10 dB below | all eight answers as one, after 26 s | 168–324 ms |

`whisper vad <audio.wav> [--partials] [--pause MS] [--legacy]` runs the
same endpointer over a file and prints what it would have done, on the
stream's clock — no model needed.

**TLS**: `--tls` mints a self-signed ECDSA-P256 certificate on the fly
(pure NURL) — browsers require a secure context before they allow
microphone capture, even on a LAN. `--cert FILE --key FILE` take real
PEMs; `wss://` works transparently.

**Access control**: by default the server is open, which is right for a
loopback bind. Give it a token — `--token TOKEN` or the `WHISPER_TOKEN`
environment variable (prefer the env var on a shared machine, where a
flag shows up in `ps`) — and every request must present it as
`Authorization: Bearer TOKEN` or `?token=TOKEN` in the query. `/health`
and the test page stay open (the page has a field to paste the token
into, remembered per browser); `/inference` and the WebSocket require it.
Binding to a non-loopback address with no token prints a warning, because
it should be a choice, not an accident.

**`GET /health`** reports the model shape, the request count and — under
`--unload-after` — whether the model is currently loaded, as JSON.

## How it is verified

Every stage is checked against an independent implementation, not against
this package's own understanding of itself:

| stage | verified against |
|---|---|
| resample → 16 kHz | scipy `resample_poly` (r = 0.99992); aliasing killed by 82 dB |
| log-mel spectrogram | HF `WhisperFeatureExtractor` — max \|Δ\| = 1.8e-5 |
| FFT (n_fft = 400) | `numpy.fft`, exact length via mixed radix |
| weights | bit-exact reads; a full forward pass at r = 1.00000000 |
| tokenizer | HF's own tokenizer, token for token |
| encoder | HF `WhisperModel.encoder`, r = 1.00000000 |
| end to end | HF `transformers` transcription, word for word — on tiny **and** distil-large-v3, CUDA **and** CPU |
| ggml container | same transcript as the safetensors checkpoint; timestamped output agrees with whisper.cpp's own CLI |

## Performance and memory

Measured on an RTX 4090; the CPU backend runs the same kernels through
OpenMP.

| | |
|---|---|
| 11 s of speech, whisper-tiny | ~0.5 s |
| 11 s of speech, distil-large-v3 | ~1.1 s (warm server: 0.33 s) |
| 292 s recording, 8 % speech, distil + `--vad` | ~1.3 s |
| large-v3 server VRAM | 4.8 GB (f16 weights stay f16 on the device) |
| large-v3 server RSS | ~130 MB (the file is mapped for the upload and released) |
| large-v3 server start / reload (page cache warm) | 0.8 s / 0.73 s (was 2.35 s) |
| large-v3 idle under `--unload-after` | ~60 MB RSS, 0 MB VRAM |

A generated token costs **456 us** on whisper-tiny (RTX 4090). Getting
there took two things, both found by measuring rather than reading: the
decoder's attention was 54 % of a step — the fused encoder kernel
amortises the key/value stream over 64 queries and a decode step has
one, so every token fell back to a path that launched `nh*hd` threads to
walk a 1500-key score row — and greedy decoding was fetching all 51865
logits per token to find the largest. The one-query attention splits the
keys across blocks and merges the partial softmaxes (cross-attention
95 us → 11, self-attention 33 → 10); the argmax reduces on the device
and returns one integer. Together: 1180 us a token → 456.

An f16 checkpoint's matrix weights are never widened to f32 in device
memory — the kernels widen at the point of use, exactly, so transcripts
are unchanged and the memory halves. This is what fits full large-v3 on
an 8 GB card. (bf16 checkpoints still widen: half of their exponent range
would not survive f16.)

## Implementation notes

* A device allocation that fails is reported, not run past. A null
  pointer does not crash a kernel — it writes nowhere and reads zeros —
  so a full card used to produce a confident transcript of nothing at
  all. `whisper` now refuses to open the model and says how much memory
  the device had.
* Whisper differs from the decoder-only shape in almost every kernel:
  LayerNorm (with bias) rather than RMSNorm, erf-GELU rather than tanh,
  two conv1d layers in front of the encoder, non-causal encoder
  attention, per-clip cross-attention K/V, and a bias-less `k_proj`.
* The prompt's control tokens (`<|startoftranscript|>`, the language,
  `<|transcribe|>`, `<|notimestamps|>`) are looked up in the checkpoint's
  own vocabulary — their ids move between whisper versions.
* ggml containers carry no special-token text at all; the loader
  synthesizes the standard spellings at whisper.cpp's positional ids, so
  both containers run through one code path.
* Every kernel is a checked one (`packages/gpukit`): it reaches device
  memory only through bounds-checked loads and stores over the buffers its
  launcher binds, so the engine is safe code end to end — no `unsafe`, no
  device addresses. The encoder, the cross-attention projections and one
  decoder step are recorded once when the model opens and replayed.
* Silero VAD's 16 kHz network is the 14 trained tensors of the ONNX file
  (`tests/silero_export.py`); its STFT basis is a periodic-Hann DFT, so it
  is computed rather than stored.
* Built on `packages/audio` (WAV, resample, mel, VAD), `packages/safetensor`,
  `packages/tokenizer`, `packages/gpukit` (CUDA + CPU backends) and
  `packages/http` (server + WebSocket) — each its own package, each with
  its own test suite.

## License

MIT OR Apache-2.0
