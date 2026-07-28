# video

Turn a video file into ordered JPEG frames — MJPEG AVI in pure NURL,
everything else through ffmpeg when it is installed.

```
video frames walk.avi --fps 10        # -> walk_frames/000000.jpg ...
video frames trip.mp4 --out frames/   # any container, via ffmpeg
video probe  walk.avi                 # what the AVI parser sees
video walk.avi                        # shorthand for `frames`, fps 10
```

## Why MJPEG is special

An AVI is a RIFF tree, and an MJPEG frame chunk **is** a complete JPEG.
Extraction is therefore parsing, not decoding: walk `hdrl`/`strl` for the
frame rate and the video stream index, walk `movi` for the `NNdc` chunks,
write the sampled ones to numbered files. No codec, no ffmpeg, no
dependency. Cameras, OBS (`ffmpeg -c:v mjpeg`) and phone apps can all
record MJPEG.

Every other container (H.264/MP4, HEVC, VP9, MKV, WebM) needs a real
decoder, and that is ffmpeg's fight; when it is on PATH it is used with
the same fps sampling, and when it is not the error says what to install
or how to record instead.

## Library

```nurl
$ `deps/video/src/video.nu`

( vid_is_video path )                     → b        the extension is a video's
( vid_frames_dir path )                   → String   <dir>/<stem>_frames
( vid_extract path fps outdir verbose )   → !i String   frames kept
( vid_avi_open path )                     → !VidAvi String
( vid_avi_extract v outdir stride )       → !i String
( vid_avi_close v )                       → v
```

`vid_extract` is the front door: it creates `outdir`, removes exactly the
frames a previous extraction left there (six digits + `.jpg`/`.png`,
nothing else — a shorter run must not inherit a longer run's tail), and
keeps every `round(src_fps / fps)`-th frame.

## Tests

```
./tests/video_test.sh
```

The fixture generator (`tests/make_avi.py`, Pillow + struct, no ffmpeg
and no cv2) doubles as documentation of the exact container layout the
parser reads.
