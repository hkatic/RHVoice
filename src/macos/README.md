# RHVoice for macOS

The macOS port: the RHVoice engine as a static library, an Audio Unit app extension that
provides voices to VoiceOver and every other speech client (macOS 13 and later), and the
RHVoice app that downloads and manages voices.

```
scripts/build.sh            # build the app (Release)
scripts/build.sh RHVoiceCLI # build rhvoice-cli for command-line synthesis
```

See [doc/en/Compiling-on-macOS.md](../../doc/en/Compiling-on-macOS.md) for requirements,
signing, troubleshooting and the layout of this directory.

| Directory | Contents |
|---|---|
| `Config/` | xcconfig files, entitlements, `Local.xcconfig.template` |
| `RHVoiceCore/` | stub `config.h` and the Objective-C++ bridge around the engine |
| `RHVoiceSynthesizer/` | the `AVSpeechSynthesisProviderAudioUnit` extension |
| `RHVoice/` | the SwiftUI app: model (index, installer, sample player) and views |
| `Shared/` | code compiled into both the app and the extension (paths, catalog, preferences) |
| `RHVoiceTests/` | XCTest suite |
| `ThirdParty/stb_vorbis/` | public-domain Ogg Vorbis decoder for demo clips |
| `scripts/` | build, metadata and localization generators, verification tools, notarization |
