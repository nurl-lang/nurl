# audio

Read WAV, resample it honestly, and compute the log-mel spectrogram a
speech model actually eats — in pure NURL.

```
nurlpkg install audio
```

```
$ audio info speech.wav
wav — 44100 Hz, 2 ch, 16 bit, 132300 frames (3 s)

$ audio resample speech.wav speech16k.wav --rate 16000

$ audio mel speech16k.wav -o mel.f32
mel — 3000 frames x 80 mels → mel.f32

$ audio vad meeting.wav
59.85 - 71.2 s
190.85 - 202.2 s
vad — 2 segment(s), 7.77 % of the audio is speech

$ audio mp3 speech.wav speech.mp3 --bitrate 128
mp3 — 269184 bytes at 128 kbit/s → speech.mp3
```

## Three places a mistake hides

**The WAV reader treats the file as untrusted.** Every chunk announces
its own size, and a file is free to lie: a `data` chunk claiming 2 GB
behind two bytes, a 0 Hz sample rate, 0 channels, a 12-bit depth nobody
has ever used, a header that stops mid-chunk. All of them are a clean
error — none of them is an allocation sized by a number a stranger chose.
8-bit unsigned, 16/24/32-bit PCM and 32/64-bit IEEE float all come back
as f32 in [-1, 1].

**Resampling is windowed-sinc, not linear interpolation.** Linear is the
tempting one-liner and it is a *lousy low-pass filter*: downsampling with
it folds everything above the new Nyquist frequency back into the speech
band — precisely where the model is listening. A 12 kHz tone resampled
44.1 → 16 kHz should vanish, not reappear at 4 kHz. Here it lands at
**−82.6 dB**, and the test suite fails if it climbs above −60.

**The mel spectrogram is whisper's, to the constant.** Every one of these
was read out of transformers' source, not remembered — and every one of
them silently changes what the model hears:

| | |
|---|---|
| window | **periodic** Hann, `hanning(N+1)[:-1]` — the symmetric one is a different window |
| padding | **reflect**, by `n_fft/2` — so frame *k* is *centred* on sample *k·hop*, not started there |
| mel scale | **Slaney** (linear below 1 kHz, log above) — not HTK's `2595·log10(1+f/700)` |
| filters | Slaney-normalised, `2/(f[k+2] − f[k])` |
| after | drop the last frame, `log10`, floor at `max − 8`, then `(x + 4)/4` |

## Verified against the thing itself

Not against my own understanding of it:

* **log-mel == Hugging Face's `WhisperFeatureExtractor`**, on real audio:
  max |Δ| = **1.8e-5**, mean |Δ| = 8.0e-9, correlation **1.00000000**
  over all 80 × 3000 values. (The residual is f32 storage rounding.)
* the resampler tracks scipy's `resample_poly` at r = 0.99992, and kills
  the out-of-band tone by 82 dB
* an independent numpy reference (`tests/mel_ref.py`) guards against
  regressions when transformers is not installed
* every bit depth round-trips; six malformed files are six clean errors;
  ASan/LSan clean

## Finding the speech

A recording is mostly not speech, and a speech model does not get cheaper
by running over silence — it costs exactly the same. `vad_segments` says
where the speech is.

It is an **energy** detector, and being clear about that matters, because
it decides where it fails: it hears "something loud enough, often enough"
rather than "a human voice", and it will call a slammed door speech.
faster-whisper reaches for Silero, a small neural VAD, for exactly that
reason. This is the honest version of what can be done without a second
model, and the seam is here for one.

What it is *not* is a fixed threshold. A fixed dB threshold works on the
file it was tuned on and nowhere else. The floor here is the **10th
percentile of this recording's own frame energies** — whatever the quiet
part of *this* room sounds like — and speech is what stands 6 dB above it
for 250 ms. Gaps under 400 ms are bridged (that is a pause between words,
not between sentences) and 200 ms is kept either side, because speech
starts before it gets loud and a word's tail is quiet.

`vad_extract` gives back the audio with the silence taken out — keeping at
most `max_gap` samples of the real room between segments. That cap is not
a detail: glue two utterances together with *nothing* between them and a
speech model hears one utterance where there were two.

`vad_extract_runs` additionally hands back the condensation **map** — one
`VadRun { cond, orig, len }` per surviving stretch — because a model
transcribing the condensed audio reports times in the condensed timeline,
and a caller who wants to say "this was said at 3:12 of the recording" has
to walk the map back. `vad_map_sample` does.

## Encoding MP3

`mp3_encode` is MPEG-1, MPEG-2 and MPEG-2.5 Layer III, in NURL: the
polyphase analysis filterbank, the 18-point MDCT with its alias-reduction
butterflies, the quantiser's step-size search, and Huffman coding over the
big-values regions and the count1 quadruples. All nine sample rates the
format defines (32/44.1/48 kHz, 16/22.05/24 kHz, 8/11.025/12 kHz), mono or
stereo, constant bitrate. No ffmpeg, no subprocess, no codec library.

**There is no psychoacoustic model**, and saying so is the honest
description of the quality. With no masking threshold there are no
scalefactors, so every band gets the same step size, chosen only to fill
the frame: the bits go where the signal is loud, not where the ear is
deaf. Long blocks only, because deciding when to switch windows is itself
a psychoacoustic decision. For speech at 128 kbit/s the difference is not
audible; for music at 64 it would be. This is the quality shape of the
fixed-point encoder `shine`, and the comparison below is against it.

The arithmetic is f64 but mirrors a fixed-point encoder's exactly — that
is what the three factors of 0.5 in the filterbank and the MDCT are for —
so a sample of 1.0 is what a decoder calls full scale and the quantiser
lands on the same integers.

| | |
|---|---|
| frames byte-identical to `shine`, 17 s of speech | **454 / 702** |
| round-trip SNR, this encoder vs `shine` | 18.13 dB vs 18.13 dB |
| encoding 16.8 s of 24 kHz mono | 69 ms |

**The test needs no decoder.** Every frame header says how long its frame
is, so a correct file is a chain: the next sync word must land exactly
where the previous frame's length says it will. `tests/mp3_frames.py`
walks that chain and fails if one bit was written short or long anywhere
in the bitstream — at all nine rates, mono and stereo. When ffmpeg is
installed the suite also decodes one back and compares waveforms
(correlation 1.0000).

## Built on

`stdlib/std/fft.nu`. Padding 400 to 512 does not compute a rounder
spectrum; it computes a different one — so 400 is transformed *exactly*,
and how it is transformed is picked by what 400 actually is: `2^4·5^2` is
perfectly factorable, so it takes the **mixed-radix** Cooley-Tukey path
(Bluestein, the chirp-z fallback, is for lengths with a large prime
factor — a 997-point frame would take it; a 400-point one paying for two
1024-point transforms to get one 400-point answer was the wrong deal).
A real signal of even length is also **folded** first: 400 real samples
become a 200-point complex transform plus an O(n) untangle, and half the
transform is half the work.

The whole 30-second mel spectrogram (3000 frames) takes about 0.14 s,
down from 0.52 when every frame went through Bluestein at full length.

## License

MIT OR Apache-2.0
