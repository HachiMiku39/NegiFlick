#!/bin/zsh
set -eu
TASK_APP_ROOT=${0:A:h:h}
TASK_BUILD_ROOT=$TASK_APP_ROOT/../../work/codecs-rebuild
TASK_DEV=${DEVELOPER_DIR:-$(xcode-select -p)}
mkdir -p "$TASK_BUILD_ROOT"
[[ -d "$TASK_BUILD_ROOT/ffmpeg-9.0.1" ]] || tar -xJf "$TASK_APP_ROOT/Vendor/Sources/ffmpeg-9.0.1.tar.xz" -C "$TASK_BUILD_ROOT"
for task_platform in iphonesimulator iphoneos; do
 task_sdk=$(DEVELOPER_DIR=$TASK_DEV xcrun --sdk $task_platform --show-sdk-path)
 task_target=arm64-apple-ios17.0
 [[ $task_platform != iphonesimulator ]] || task_target=arm64-apple-ios17.0-simulator
 task_prefix=$TASK_APP_ROOT/Vendor/$task_platform
 mkdir -p "$TASK_BUILD_ROOT/build-$task_platform"
 cd "$TASK_BUILD_ROOT/build-$task_platform"
 "$TASK_BUILD_ROOT/ffmpeg-9.0.1/configure" --prefix="$task_prefix" --enable-cross-compile --target-os=darwin --arch=aarch64 --cc="$TASK_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang" --sysroot="$task_sdk" --extra-cflags="-target $task_target -fPIC" --extra-ldflags="-target $task_target" --disable-everything --disable-programs --disable-doc --disable-network --disable-autodetect --disable-asm --disable-avdevice --disable-avfilter --disable-swresample --enable-avcodec --enable-avformat --enable-swscale --enable-decoder=mpeg1video,adpcm_adx --enable-demuxer=usm --enable-protocol=file --enable-parser=mpegvideo --enable-static --disable-shared
 make -j8
 make install
 "$TASK_DEV/Toolchains/XcodeDefault.xctoolchain/usr/bin/libtool" -static -o "$task_prefix/libMikuMedia.a" "$task_prefix/lib/libavformat.a" "$task_prefix/lib/libavcodec.a" "$task_prefix/lib/libavutil.a" "$task_prefix/lib/libswscale.a"
done
python3 "$TASK_APP_ROOT/Tools/sanitize-public-dependencies.py"
