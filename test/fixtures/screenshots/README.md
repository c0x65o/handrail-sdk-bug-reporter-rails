# Screenshot fixtures

`pixel.png` and `pixel.jpg` are synthetic white 1x1 RGB images, generated locally
with FFmpeg's color source and image encoders. They contain no application or
user data and require no network to generate or consume.

Generation commands (FFmpeg 5.1.9, libavcodec 59.37.100):

```sh
ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=white:s=2x2 -vf scale=1:1 -frames:v 1 -threads 1 -n test/fixtures/screenshots/pixel.png
ffmpeg -hide_banner -loglevel error -f lavfi -i color=c=white:s=2x2 -vf scale=1:1 -frames:v 1 -threads 1 -n test/fixtures/screenshots/pixel.jpg
```

Tests derive explicit base64/data URLs from these bytes. Boundary tests append
synthetic bytes in memory to exercise the signature/size contract without
checking in a 20 MiB fixture. Complete image decoding is outside that contract.
