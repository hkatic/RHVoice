`stb_vorbis.c` is the single-file Ogg Vorbis decoder from https://github.com/nothings/stb
(public domain or MIT, at your option; see the end of the file). It is used by the RHVoice
app to play the demo clips that the package index serves as Ogg Vorbis files, which macOS
cannot decode natively. Update by replacing `stb_vorbis.c` with a newer upstream copy.
