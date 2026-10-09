# NegiFlick

**A keyboard rhythm game for iPhone and iPad.**

Turn kana, Chinese characters, and English words into rhythm targets. Tap or flick the in-game keyboard to the music, build a combo, and create your own charts.

**输入法音游：跟随音乐，用轻点和滑动输入假名、汉字拼音首字母或英文单词首字母。**

NegiFlick is a standalone development project derived from [MikuFlick64](https://github.com/HachiMiku39/mikuflick64). It uses independently generated visual and audio assets. The application does not bundle SEGA game artwork, recordings, movies, voices, or fonts. See [asset provenance](ASSET-PROVENANCE.txt) for the original sound-generation checks.

## Play in three languages

| Chart language | One note represents | Input example |
| --- | --- | --- |
| Japanese / 日文 | One kana / 一个假名 | Tap or flick the kana keyboard |
| Chinese / 中文 | One Chinese character / 一个汉字 | `你好` → `N`, `H` |
| English / 英文 | One word / 一个单词 | `Hello world` → `H`, `W` |

The chart selects its keyboard. The interface language and lyric translations do not change the input mode. Chinese charts can specify a pronunciation for polyphonic characters. English targets show the full word alongside its initial.

中文和英文共用字母分组键盘：组内第一字母轻点，第二左滑，第三上滑，第四右滑。中文每字只输入拼音首字母；英文每词只输入首字母，不需要输入完整拼音或拼写。

Difficulty and judgement names remain English in every interface language: `EASY`, `NORMAL`, `HARD`, `EXTREME`, `BTL`; `COOL`, `FINE`, `SAFE`, `SAD`, `WORST`, `FAST`, and `LATE`.

## Get the game

**Current version: 0.1.0, development prototype.** Source code is available in this repository. There is no NegiFlick IPA or App Store listing yet. App Store distribution is a planned direction.

- iOS / iPadOS 17 or later.
- iPhone and iPad layouts, with safe-area handling for the Duo simulator's folding configurations.
- ProMotion support up to 120 Hz on supported displays; actual refresh rate depends on the device and system settings.
- An original 30-second practice track, **Kana Sprint**, is included.

## Songs and custom charts

Choose a ZIP or folder through the app's import controls. A custom pack contains `negiflick-pack.json`, its chart JSON, video with an audio track, and optional cover art and translations. Each pack describes its own input language and enabled difficulties.

Try the included original practice packs:

- [English: Word Initial Sprint](Examples/english-demo.zip) — eight words, eight initial targets.
- [Chinese: 你好 · 首字母音游](Examples/pinyin-demo.zip) — six characters, six pinyin initials.
- [Chart format and authoring guide](CHART-FORMAT.txt).

The importer also retains compatibility with user-provided legacy `Mov_*` / `Thum_*` song-pack ZIP, RAR, and folder formats. The original MikuFlick2 initial songs can also be imported from a folder or archive containing their flat `.usm` files and `music_00_01` through `music_00_04` artwork atlases. They are registered as `Mov_0`; an App/Payload wrapper is supported, and application executables are never run. Original song packs are not distributed here. NegiFlick packs are a separate format and are not compatible with AstroDX's `.adx` format.

其他功能包括 CLASSIC / GRID / LIST 选曲、MV、歌词与译文导入、带进度与速度的并发下载列表，以及开发者自动演奏和性能提示。应用通过用户选择的文件或目录访问内容，网络下载使用 HTTPS。

## Build and develop

1. Open `NegiFlick.xcodeproj` in Xcode.
2. Select the **NegiFlick** scheme and your simulator or device.
3. For a physical device, select your own signing team in **Signing & Capabilities**.
4. Build and run. The bundle identifier is `com.sbga.NegiFlick`.

The bundled FFmpeg libraries, exact source archive, rebuild script, and LGPL notices are included. See [third-party notices](Vendor/NOTICE.md). Graphics and practice audio can be regenerated with `Tools/GenerateArtwork.swift` and `Tools/SynthAudio.py`.

For chart compilation and gameplay checks, see [test instructions](Tests/README.txt). See [validation notes](VALIDATION.txt) for the precise simulator coverage and remaining limitations.

The latest initial-input samples completed automatic play on the iPad Pro simulator: English **8 COOL / 2600**, Chinese **6 COOL / 1900**. Earlier iPhone Air and Duo observations are recorded separately; they are not a complete test of the latest revision on every device or form. Physical-device manual play has not been fully validated.

## Feedback

Report bugs through [GitHub Issues](https://github.com/HachiMiku39/NegiFlick/issues). Include the app version, device, screen orientation or folding configuration, input language, reproduction steps, and a screenshot where useful. A minimal original chart is especially helpful for import problems.

欢迎提交问题、原创谱面格式建议和布局反馈。请说明设备形态与具体页面，便于复现。

## Inspiration and project status

The presentation and separation of the app from user-imported levels are inspired by [AstroDX](https://github.com/2394425147/astrodx) and its [installation guide](https://wiki.astrodx.com/en/install/ios). NegiFlick does not use AstroDX code, artwork, or chart formats and is not affiliated with AstroDX or SEGA.

NegiFlick retains the gameplay rules researched in MikuFlick64; it is not presented as a clean-room implementation. This repository provides source for development and review. No application-source license has been selected yet; third-party components retain their own licenses. App Store submission has not taken place.
