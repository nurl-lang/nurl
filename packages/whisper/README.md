# whisper

Speech recognition in pure NURL. Real audio in, real text out — running
from the safetensors checkpoint Hugging Face ships, on the GPU or the CPU.

```
nurlpkg install whisper
```

```
$ whisper transcribe ./whisper-tiny jfk.wav
 And so my fellow Americans ask not what your country can do for you ask what you can do for your country.
```

Word for word what HF transformers produces from the same model — and the
CPU backend produces the same text as CUDA.

Bigger models just work, because nothing is hardcoded to a shape:

```
$ whisper transcribe ./distil-large-v3 jfk.wav
 And so, my fellow Americans, ask not what your country can do for you. Ask what you can do for your country.
```

(128 mel bands instead of 80, 1280-wide, 32 encoder layers and 2 decoder
layers — every one of those read out of the model's own `config.json`.)

A model directory is what Hugging Face ships: `config.json`,
`model.safetensors`, `tokenizer.json`, side by side.

## Built package by package

Nothing here is a black box, and every stage is verified against an
independent implementation rather than against my own understanding of it:

| stage | package | verified against |
|---|---|---|
| WAV → 16 kHz mono | `audio` | scipy's `resample_poly` (r = 0.99992); a tone above the new Nyquist is killed by 82 dB |
| → log-mel | `audio` | HF's `WhisperFeatureExtractor` — max \|Δ\| = 1.8e-5, r = 1.00000000 |
| n_fft = 400 (not a power of two) | `stdlib/std/fft.nu` | numpy's `np.fft` — Bluestein, 1.9e-14 |
| weights | `safetensor` | 167 tensors bit-exact; a whole forward pass at r = 1.00000000 |
| vocabulary | `tokenizer` | HF's own tokenizer, 20/20 strings |
| encoder + decoder | this package | HF's `WhisperModel.encoder` (r = 1.00000000) and its transcription, word for word — on whisper-tiny **and** distil-large-v3 |

## Whisper is not the llama shape

Every kernel is a place it differs:

* **LayerNorm**, not RMSNorm — it subtracts the mean, and it has a bias.
* **GELU with the error function**, not the tanh approximation. Gemma
  wants the other one; they are different functions.
* **conv1d**, twice (stride 1 then 2) — that is what turns 3000
  spectrogram frames into 1500 encoder positions.
* **Non-causal attention.** Every attention in this ecosystem before this
  masked the future. A speech encoder hears the whole 30 seconds at once.
* **Cross-attention**: the decoder's queries, the *encoder's* keys and
  values — computed **once per clip**, not once per generated token.
* **`k_proj` has no bias**, alone among the projections.

## `--vad`: the model never sees the silence

```
$ whisper transcribe distil-large-v3 meeting.wav
 Thank you. Thank you. And so, my fellow Americans, ask not what your country
 can do for you. Ask what you can do for your country. Thank you. Thank you.
 Thank you. […]                                                       13.3 s

$ whisper transcribe distil-large-v3 meeting.wav --vad
 And so, my fellow Americans, ask not what your country can do for you. Ask
 what you can do for your country.                                     2.2 s
```

Two things are wrong with the first one, and only one of them is the clock.

A recording is mostly not speech, and whisper costs exactly the same over a
silent 30 seconds as over a spoken one — so on a 292-second recording that is
8 % speech, essentially the whole bill is silence. That is the 13.3 s.

But whisper handed silence does not stay quiet. It was trained on audio that
had somebody talking in it, so asked what was said when nothing was, it
answers anyway: `[BLANK_AUDIO]`, `[silence]`, `Thank you.` The `Thank you.`
above is not a bug in this implementation — it is what the checkpoint says.

`--vad` finds the speech first (packages/audio) and hands the model only that,
with a half-second of the real room kept between segments so two utterances do
not run together. Where there is speech the words are unchanged, byte for
byte. Where there is none, there is now nothing to hallucinate about.

It also rescues speech the windowing would otherwise eat. The encoder sees
exactly 30 seconds, so an utterance that straddles a window boundary is cut in
half — and distil, handed the back half of a sentence, returns
` And so my fellow Americans country.` VAD moves the boundary off the speech.

## `--timestamps`: the model's own clock, in the recording's timeline

```
$ whisper transcribe distil-large-v3 meeting.wav --vad --timestamps
[00:59.85 --> 01:07.49] And so, my fellow Americans, ask not what your country can do for you.
[01:08.21 --> 01:10.39] Ask what you can do for your country.
[03:10.84 --> 03:18.48] And so, my fellow Americans, ask not what your country can do for you.
[03:19.20 --> 03:21.38] Ask what you can do for your country.
```

The timestamps are whisper's own: leave `<|notimestamps|>` out of the prompt
and the model interleaves timestamp tokens (`<|0.00|>` … `<|30.00|>`, one per
20 ms) with the words — it was trained to. But greedy decoding alone almost
never emits one, and the reason is worth stating: no *single* 20 ms bin ever
outscores "the". A spoken boundary spreads its probability over dozens of
bins, so the bins win **collectively or not at all** — which is exactly what
openai's constrained-decoding rules encode (the summed timestamp probability
is compared against the best text token; timestamps open every window, never
run backwards, and come in close-open pairs). Those rules are implemented
here, on the host, over the same logits either backend produced.

Under `--vad` there is a second translation. The model transcribed *condensed*
audio — second 0.2 of what it heard may be second 20 of the file — so every
timestamp is walked back through the condensation map (`VadRun`, from
packages/audio) before it is printed. A subtitle at `00:00.20` for words
spoken at `00:20` would be worse than no subtitle at all; the four lines
above land on the recording's real clock.

## `whisper serve`: the model held open

```
$ whisper serve distil-large-v3 --addr 0.0.0.0:6543
whisper serving on http://0.0.0.0:6543 (POST /inference, GET /health)

$ curl -F file=@jfk.wav http://localhost:6543/inference
{"text":"And so, my fellow Americans, ask not what your country can do for you. Ask what you can do for your country."}
```

The point of a server is *when the model loads*. The CLI pays the whole
bill per invocation — read 1.5 GB of safetensors, convert f16 to f32 on
the device, compile the kernels — and only then hears the audio. The
server pays it once, before the port opens: the same 11-second clip that
costs the CLI 1.15 s costs a warm request **0.33 s**.

The HTTP surface is whisper.cpp's server, so its clients work unchanged:
`POST /inference` with a multipart `file` field, optional `language` and
`response_format` (`json`|`text`) fields. Two additions, both because
there was no reason not to: a **raw WAV body** works (`curl --data-binary`
is not a browser form and does not have to pretend to be one), and
per-request `vad=true` / `timestamps=true` fields override the server
flags — one server serves both a subtitle pipeline and a bare-text one.

## The same port speaks WebSocket

```
$ ws://host:6543/          # any path — the Upgrade header is the router
→ {"format":"pcm16"}                                (optional config first)
← {"status":"ok","format":"pcm16","vad":"adaptive-floor"}
→ <binary frames: raw PCM16 @ 16 kHz>
← {"text":" And so my fellow Americans.","t0":0.09,"t1":2.33}
← {"text":" Ask what you can do for your country.","t0":7.97,"t1":11.2}
```

Live audio in, utterances out — segmented by the **streaming** VAD
(`VadStream`, packages/audio): the noise floor is the 10th percentile of
the trailing minute, recomputed every second, because a room changes and
a frozen floor calls the new fan speech forever. `t0`/`t1` are seconds on
the stream's own clock. A run that reaches 28 s closes forcibly —
whisper's window is 30 s, and a lecture has no obligation to pause.

The whisper.cpp fork this is modelled on needs a **second port** for its
WebSocket (its HTTP and WS stacks cannot share one), a **fixed dB
silence threshold**, and a pile of `auto_settings` heuristics that exist
to keep re-tuning that threshold per room. One port, and a floor that
tunes itself, replace all three.

## f16 weights stay f16

An f16 checkpoint's matrix weights — the projections, the FFN layers, the
embedding, which is where all the parameters live — used to be widened to
f32 on the device. That doubled the memory for nothing: the halves *are*
the model. They now stay f16, and the kernels widen at the point of use —
exactly, denormals included — so the arithmetic is f32 either way and the
transcripts are identical.

| distil-large-v3 server | VRAM |
|---|---|
| before (f32 expansion) | 3.9 GB |
| now (f16 on device) | **2.4 GB** |

Half the weight bytes is also half the traffic through a memory-bound
matvec, so decoding got slightly faster too. A mixed-precision checkpoint
(none exists in practice) falls back to the f32 expansion — one probe, one
predicate, used by both the probe and the upload so they cannot disagree.

## whisper.cpp's ggml models load directly

```
$ whisper transcribe ggml-large-v3.bin meeting.wav --vad --timestamps
```

The `ggml-*.bin` files ggerganov ships are how whisper models actually move
between machines, and one is fully self-contained: hyperparameters, the
vocabulary and every tensor in a single file. Point any command at one —
`transcribe`, `serve`, the WebSocket stream — and it just works, with the
same transcript word-for-word as the HF checkpoint (they are the same
weights).

Two translations happen at load, and only at load: whisper.cpp keeps
OpenAI's tensor names (`encoder.blocks.0.attn.query.weight`), which are
mapped to the HF names the model layer speaks; and the special tokens,
which the ggml vocabulary does not carry as text at all — whisper.cpp
derives their ids positionally — are synthesized with their HF spellings
(`<|startoftranscript|>`, `<|fi|>`, `<|0.00|>` …) at those positions, so
name-based lookup, the timestamp rules and decoding run unchanged. ggml
matrices are f16 even in the smallest file, so they ride the half mode
natively. Quantised ggml files are refused with a clear message, for now.

## The server has a face

`GET /` on a running `whisper serve` is a built-in test page: drop an
audio file on it (language / vad / timestamps toggles included), or press
**Start microphone** and watch utterances land as you pause — the page
resamples your microphone to 16 kHz PCM16 in the browser and streams it
over the same port's WebSocket, which is exactly the protocol any other
client would use. The page lives in `views/index.html` and is staged by
`nurlpkg install` into `share/whisper/` (the manifest's `[install].assets`
— the same mechanism as packages/anomaly's dashboard), where the server
finds it beside its own binary; running from the package directory works
too, and a missing page degrades to a pointer, not a broken server.

## The control tokens are looked up, not hardcoded

A whisper prompt is four tokens — `<|startoftranscript|>`, the language,
`<|transcribe|>`, `<|notimestamps|>` — and they are the model being *told
what task it is doing*. Their ids move between whisper versions (v3 added
a language, and every id after it shifted), so they are looked up in the
vocabulary the checkpoint ships with.

## License

MIT OR Apache-2.0
