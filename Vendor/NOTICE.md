This project includes FFmpeg 9.0.1 avformat/avcodec/avutil/swscale, built without GPL, nonfree, networking, external codec, or command-line program support. Only USM demuxing, MPEG-1 video/ADX audio decoding, video parsing and pixel format conversion are enabled. AVFoundation performs H.264/AAC encoding on iOS.

FFmpeg is licensed under LGPL 2.1 or later. License texts and the exact source tarball are supplied here. `Tools/build-codecs.sh` rebuilds both arm64 libraries. All application source is supplied in this project; rebuild the application in Xcode with a modified library to relink it. Do not remove these notices when redistributing the library.

ZIP, RAR4 and RAR5 extraction uses the operating system's libarchive. No command-line FFmpeg executable is bundled with the application.

NegiFlick includes only independently generated graphics, audio and its original practice track. User-imported media remains external to the distribution. Compatibility filenames and metadata identify formats; no original game artwork, samples, voices, movies or font binaries are supplied.

Published static libraries have debug records stripped and local installation prefixes replaced with equal-length public build placeholders in FFmpeg's read-only configuration strings. Executable code and linkage symbols are retained. pkg-config metadata uses relocatable paths. `Tools/sanitize-public-dependencies.py` performs this metadata cleanup after a rebuild.
