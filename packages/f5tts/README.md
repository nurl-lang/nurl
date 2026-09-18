# f5tts

F5-TTS — the flow-matching text-to-speech model — in pure NURL. A reference
recording and its transcript go in; the same voice comes out saying something
it never said. No Python, no PyTorch, no ONNX export.

```
nurlpkg install f5tts
```

```
$ f5tts synth --model owner/repo/model.safetensors \
              --vocoder owner/repo/pytorch_model.bin \
              --voice ~/.f5tts/voices/narrator \
              --text "The line it should read." -o out.wav
f5tts: loaded in 590 ms
f5tts: 1.08 s of audio in 806 ms
f5tts: wrote out.wav

$ f5tts serve --model <name> --vocoder <name> --addr 127.0.0.1:7861
```

## Naming a model

**This package ships no checkpoint, no default and no catalogue.** A speech
model is a choice about a language, a voice and a licence, and none of those
are a library's to make. `--model` and `--vocoder` are required, and each
takes one of three forms, tried in this order:

| form | what it is |
|---|---|
| a path | a file, or a directory holding a checkpoint and its `vocab.txt` |
| a name | a directory under `~/.f5tts/models` — where a fine-tune or a training run lands |
| `owner/repo/path/to/file` | a repository reference, fetched once into the shared `~/.nurl/models` cache |

The vocabulary is taken to be `vocab.txt` beside the checkpoint, which is how
the releases are laid out; `--vocab` overrides it. `$F5TTS_HOME` moves the
whole directory. A machine that has just installed this has no models and can
reach any reference: `serve` works, and the first request pays the download.

## The service

`f5tts serve` answers `POST /tts` and `POST /dialogue` in the shape the
reference FastAPI service takes, plus `GET /voices`, `GET /models`,
`POST /voices/add`, `DELETE /voices/{id}` and a single-page interface at `/`
that is one string in the binary — no build step, no CDN, so a machine with no
network still gets a working UI.

`output_format` is `wav`, `mp3` or `pcm`. The mp3 is encoded by
[packages/audio](../audio) in NURL, not handed to ffmpeg, so the service runs
no subprocess and links no codec library. `model_id` in a request switches
models (~450 ms); `--unload-after N` gives the card back after N idle seconds
and the next request reloads.

One thread owns the GPU behind a job queue, with fibers on the sockets. A CUDA
context belongs to a thread and the device holds one copy of the activations,
so a dialogue of eight lines is eight jobs answered in turn rather than eight
forwards through the same scratch.

## The quality gate

A flow-matching model given a duration estimate and some noise does not
always say the words: it drops a short one, runs two together, mumbles the end
of a chunk whose duration guess was tight — and nothing inside the model says
so. So the service can LISTEN. With `--whisper HOST:PORT` naming a transcriber
(whisper.cpp's server or [packages/whisper](../whisper) — both answer
`POST /inference`), three request fields turn the gate on, the same three the
reference service takes:

| field | meaning |
|---|---|
| `max_wer` | the word error rate a line has to stay under (default 0.15 once the gate is on) |
| `whisper_retry` | how many MORE times a line may be generated when it is over — retries, so `0` generates once and `3` at most four times (default 0) |
| `splitfail` | when a line is still over after N attempts, generate it again a sentence at a time and keep whichever came out better (default 0 = never) |

Asking for either of the first two turns the gate on; each is also accepted
per input, in `voice_settings`. What was heard comes back in the response
headers `x-f5tts-word-errors`, `x-f5tts-words`, `x-f5tts-attempts` and
`x-f5tts-unheard` — the last is the number of chunks the transcriber never
answered for, so a quiet transcriber cannot pass as a perfect one.

The gate works chunk by chunk, not line by line: a retry regenerates the
chunk that came out wrong, from a different seed, and the BEST attempt is
kept rather than the last, because a retry can come out worse. It measures
what the model said, not how the transcriber spelt it — digits are read out
in Finnish before comparing (`2026` meets *kaksituhatta kaksikymmentäkuusi*),
a hyphen is a word boundary, and a compound the transcriber joined or split
(*lepakonkosto* for *lepakon kosto*) costs nothing.

Two remedies the gate leans on, both under `--short-fix`. A line that opens
with a one-word sentence ("Juuri. Seuraavaksi…") is generated with that word
as its own chunk, because run straight on from the reference the model skips
it — from every seed — and said on its own it comes out fine. And a short
line gets its linear duration estimate plus a fixed overhead of 1.1 s
(tapering to nothing at 120 bytes), because the reference's estimate is a
speaking RATE and a short line is mostly not speaking. Measured on eleven
one-to-three-word lines, two voices, two seeds each: 0.8 s of generated
audio comes back as silence, 1.2 s clipped, 1.6–2.0 s right, and from 2.5 s
up the model fills the room by saying the line twice or carrying on with
the reference text — 3 word errors in 84 at linear + 1.1 s against 12 for the
speed table the upstream notes propose and 65 for a 0.8 s floor.

## Verified against the reference, stage by stage

With **fixed inputs**, so a disagreement is about the model and not about
sampling:

| stage | relative error |
|---|---|
| text front-end, id for id over 3039 lines | exact |
| mel, against an independent float64 reference | exact |
| text encoder | 2.6e-6 |
| the whole 22-block forward | 2.3e-6 |
| 32 guided ODE steps | 7.4e-6 |
| waveform | 2.9e-4 |

`tests/ref_dit.py` and `tests/ref_gen.py` dump the reference's own
intermediates; `tests/f5tts_test.sh` compares against them. Both take their
paths from the environment and hardcode nothing.

## Three things this port had to learn the hard way

**The text front-end is jieba, and jieba's character class is ASCII.** It has
no `ä`, `ö` or `å`, so a word containing one breaks at every such letter, and
the rule that spaces multi-character ASCII segments then fires *inside* the
word: `Yöllä` is read as `Yö llä`. Checkpoints for those languages were
fine-tuned through exactly that, so reproducing the quirk is not optional.

**Vocabulary row 0 is the filler token's embedding, not a hole.** Skip it and
the unconditional half of classifier-free guidance is left with the position
code and nothing else — 20 % off the velocity, and invisible in the
conditional half, which is where anyone would look.

**The reference mel is restored over the first frames before the cut**, one
frame further than the conditioning reaches, and the result is rescaled by the
recording's own loudness. Get either wrong and every intermediate still
matches while the waveform is off by a constant.

## Speed

An utterance the reference implementation takes three minutes over on this
machine's CPU takes **1.6 s** (NFE 32, one consumer GPU). Most of that came
from measuring rather than guessing: `--profile` said the position
embedding's convolution was 70 % of a synthesis while doing 2 % of its
arithmetic, because each thread walked its own slice of the weights and a
warp's 32 reads were 1984 floats apart. Permuting those weights once at upload
and computing four positions per thread took it from 45.5 ms a call to 1.5.

`--unload-after` takes device memory from 2289 MiB to 883 when idle, and
brings the weights back from the page cache in 336 ms.

## Built on

[safetensor](../safetensor) reads the DiT, [torchpt](../torchpt) reads the
vocoder's PyTorch pickle, [audio](../audio) turns the recording into the mel
and the vocoder's spectrogram back into samples (and encodes the mp3),
[gpukit](../gpukit) runs the arithmetic, [hub](../hub) fetches what is named
by reference, and [http](../http) serves.

## License

MIT OR Apache-2.0
