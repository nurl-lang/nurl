### Changed

- **map-anything: a long video gives views from its whole length, the sharp frames** (map-anything 0.9.0, video 0.3.0). `--max-views N` used to keep the first N frames; it now spreads N views over the whole capture and takes the sharpest frame of each run (variance of the Laplacian), and a video is sampled across its whole length with three candidates per view (`vid_extract_count`, the rate count/duration from ffprobe). The `serve` page's views control is a slider that says how densely it samples the video.
