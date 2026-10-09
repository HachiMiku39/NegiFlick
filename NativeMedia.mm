#import "NativeMedia.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>
#include <sys/stat.h>
#include <unistd.h>
#include <thread>
#include <atomic>
#include <vector>

#define AVMediaType FFMediaType
extern "C" {
#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>
#undef AVMediaType
struct archive; struct archive_entry;
struct archive *archive_read_new(void);
int archive_read_support_filter_all(struct archive *);
int archive_read_support_format_zip(struct archive *);
int archive_read_support_format_rar(struct archive *);
int archive_read_support_format_rar5(struct archive *);
int archive_read_open_filename(struct archive *, const char *, size_t);
int archive_read_next_header(struct archive *, struct archive_entry **);
const char *archive_entry_pathname(struct archive_entry *);
unsigned int archive_entry_filetype(struct archive_entry *);
const char *archive_entry_symlink(struct archive_entry *);
const char *archive_entry_hardlink(struct archive_entry *);
long long archive_entry_size(struct archive_entry *);
ssize_t archive_read_data(struct archive *, void *, size_t);
const char *archive_error_string(struct archive *);
int archive_read_free(struct archive *);
}
static BOOL fail(NSError **error, NSString *reason, NSError *underlying=nil) {
 if(error){NSMutableDictionary *info=[@{NSLocalizedDescriptionKey:reason?:@"Media error"} mutableCopy];if(underlying)info[NSUnderlyingErrorKey]=underlying;*error=[NSError errorWithDomain:@"MikuFlick.Media" code:1 userInfo:info];}return NO;
}
BOOL MFExtractArchive(NSString *source, NSString *destination, NSError **error) {
 // iOS exposes the sandbox through both /var and /private/var. Resolve the
 // destination and each entry consistently before testing containment.
 NSURL *rootURL=[[NSURL fileURLWithPath:destination isDirectory:YES] URLByResolvingSymlinksInPath];
 NSString *rootPrefix=[rootURL.path stringByAppendingString:@"/"];
 NSString *ext=source.pathExtension.lowercaseString;
 if(![@[@"zip",@"rar"] containsObject:ext])return fail(error,@"Only ZIP and RAR are supported.");
 struct archive *a=archive_read_new(); if(!a)return fail(error,@"Archive initialization failed.");
 archive_read_support_filter_all(a); archive_read_support_format_zip(a);archive_read_support_format_rar(a);archive_read_support_format_rar5(a);
 BOOL ok=YES;NSString *why=@"Archive extraction failed.";unsigned long long total=0;int count=0;
 if(archive_read_open_filename(a,source.fileSystemRepresentation,65536)!=0){why=@(archive_error_string(a)?:"Cannot open archive");ok=NO;}
 struct archive_entry *e;int status=0;
 while(ok&&(status=archive_read_next_header(a,&e))==0){@autoreleasepool{
  const char *raw=archive_entry_pathname(e);NSString *name=raw?[@(raw) stringByReplacingOccurrencesOfString:@"\\" withString:@"/"]:@"";
  if([name isEqualToString:@"."]||[name isEqualToString:@"./"])continue;
  NSArray *parts=name.pathComponents;
  if(name.length==0||[name hasPrefix:@"/"]||[parts containsObject:@".."]||archive_entry_symlink(e)||archive_entry_hardlink(e)||++count>20000){ok=NO;why=@"Unsafe or oversized archive.";break;}
  // Never follow a pre-existing symlink inside the extraction tree. Resolving
  // a not-yet-created leaf alone does not reliably resolve its parent links.
  NSString *walk=rootURL.path;
  for(NSString *part in parts){
   if([part isEqualToString:@"."])continue;
   walk=[walk stringByAppendingPathComponent:part];
   NSDictionary *attributes=[[NSFileManager defaultManager] attributesOfItemAtPath:walk error:nil];
   if([attributes[NSFileType] isEqual:NSFileTypeSymbolicLink]){ok=NO;why=@"Unsafe archive symlink.";break;}
  }
  if(!ok)break;
  NSString *path=[rootURL URLByAppendingPathComponent:name].URLByResolvingSymlinksInPath.path;
  if(![path hasPrefix:rootPrefix]){ok=NO;why=[@"Invalid archive path: " stringByAppendingString:name];break;}
  unsigned int type=archive_entry_filetype(e);
  if(type==S_IFDIR){if(![[NSFileManager defaultManager] createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:error]){ok=NO;why=@"Cannot write extracted file.";break;}continue;}
  if(type!=S_IFREG){ok=NO;why=@"Unsupported archive entry.";break;}
  if(archive_entry_size(e)>4LL*1024*1024*1024){ok=NO;why=@"Archive entry exceeds the limit.";break;}
  if(![[NSFileManager defaultManager] createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]){ok=NO;break;}
  FILE *f=fopen(path.fileSystemRepresentation,"wb");if(!f){ok=NO;why=@"Cannot write extracted file.";break;}
  char buf[65536];ssize_t n;
  while((n=archive_read_data(a,buf,sizeof(buf)))>0){total+=n;if(total>12ULL*1024*1024*1024||fwrite(buf,1,n,f)!=(size_t)n){ok=NO;why=@"Not enough space or archive too large.";break;}}
  if(n<0){ok=NO;why=@(archive_error_string(a)?:"Damaged archive");}fclose(f);
 }}
 if(ok&&status!=1){ok=NO;why=@(archive_error_string(a)?:"Damaged archive");}
 archive_read_free(a);return ok?YES:fail(error,why,error?*error:nil);
}

// Preview ADX files are audio only; write lossless PCM CAF without a video encoder.
static BOOL convertPreview(NSString *source, NSString *destination, NSError **error) {
 AVFormatContext *format=NULL;AVCodecContext *decoder=NULL;AVPacket *packet=av_packet_alloc();AVFrame *frame=av_frame_alloc();BOOL ok=YES;
 if(avformat_open_input(&format,source.fileSystemRepresentation,NULL,NULL)<0||avformat_find_stream_info(format,NULL)<0)ok=NO;
 int stream=ok?av_find_best_stream(format,AVMEDIA_TYPE_AUDIO,-1,-1,NULL,0):-1;
 if(stream<0)ok=NO;
 if(ok){const AVCodec *codec=avcodec_find_decoder(format->streams[stream]->codecpar->codec_id);if(!codec)ok=NO;else{decoder=avcodec_alloc_context3(codec);avcodec_parameters_to_context(decoder,format->streams[stream]->codecpar);if(avcodec_open2(decoder,codec,NULL)<0)ok=NO;}}
 AVAudioFile *file=nil;AVAudioFormat *pcmFormat=nil;
 if(ok){int ch=decoder->ch_layout.nb_channels;pcmFormat=[[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16 sampleRate:decoder->sample_rate channels:ch interleaved:YES];
  [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
  file=[[AVAudioFile alloc] initForWriting:[NSURL fileURLWithPath:destination] settings:pcmFormat.settings commonFormat:AVAudioPCMFormatInt16 interleaved:YES error:error];if(!file)ok=NO;
 }
 auto consume=[&]()->BOOL{while(avcodec_receive_frame(decoder,frame)>=0){@autoreleasepool{
  int ch=decoder->ch_layout.nb_channels,n=frame->nb_samples;AVAudioPCMBuffer *buffer=[[AVAudioPCMBuffer alloc] initWithPCMFormat:pcmFormat frameCapacity:n];buffer.frameLength=n;int16_t *samples=buffer.int16ChannelData[0];
  if(frame->format==AV_SAMPLE_FMT_S16P){for(int j=0;j<n;j++)for(int c=0;c<ch;c++)samples[j*ch+c]=((int16_t*)frame->extended_data[c])[j];}
  else if(frame->format==AV_SAMPLE_FMT_S16)memcpy(samples,frame->data[0],n*ch*2);else{return NO;}
  if(![file writeFromBuffer:buffer error:error])return NO;av_frame_unref(frame);
 }}return YES;};
 while(ok&&av_read_frame(format,packet)>=0){if(packet->stream_index==stream){if(avcodec_send_packet(decoder,packet)<0||!consume())ok=NO;}av_packet_unref(packet);}
 if(ok){avcodec_send_packet(decoder,NULL);ok=consume();}
 file=nil;av_frame_free(&frame);av_packet_free(&packet);avcodec_free_context(&decoder);if(format)avformat_close_input(&format);
 if(!ok){[[NSFileManager defaultManager] removeItemAtPath:destination error:nil];return fail(error,@"Cannot decode song preview.");}return YES;
}
BOOL MFConvertUSM(NSString *source, NSString *destination, NSError **error) {
 if([source.pathExtension.lowercaseString isEqualToString:@"adx"])return convertPreview(source,destination,error);
  AVFormatContext *format=NULL;AVCodecContext *decoders[16]={0};struct SwsContext *scale=NULL;
  BOOL ok=YES;NSString *why=@"USM conversion failed.";
  AVAssetWriter *writer=nil;AVAssetWriterInput *inputs[16]={nil};AVAssetWriterInputPixelBufferAdaptor *adaptor=nil;
  long long audioSamples[16]={0};long long videoFrames=0;int vi=-1;CMFormatDescriptionRef audioFormats[16]={NULL};
  if(avformat_open_input(&format,source.fileSystemRepresentation,NULL,NULL)<0||avformat_find_stream_info(format,NULL)<0){ok=NO;why=@"Cannot read USM streams.";}
  if(ok&&format->nb_streams>16){ok=NO;why=@"Too many media streams.";}
  if(ok){
   [[NSFileManager defaultManager] removeItemAtPath:destination error:nil];
   writer=[[AVAssetWriter alloc] initWithURL:[NSURL fileURLWithPath:destination] fileType:AVFileTypeMPEG4 error:error];if(!writer)ok=NO;
  }
  if(ok)for(unsigned int i=0;i<format->nb_streams;i++){
   AVStream *s=format->streams[i];enum FFMediaType type=s->codecpar->codec_type;if(type!=AVMEDIA_TYPE_VIDEO&&type!=AVMEDIA_TYPE_AUDIO)continue;
   const AVCodec *codec=avcodec_find_decoder(s->codecpar->codec_id);if(!codec){ok=NO;why=@"Unsupported USM codec.";break;}
   decoders[i]=avcodec_alloc_context3(codec);avcodec_parameters_to_context(decoders[i],s->codecpar);if(avcodec_open2(decoders[i],codec,NULL)<0){ok=NO;break;}
   if(type==AVMEDIA_TYPE_VIDEO){
    vi=i;int w=decoders[i]->width,h=decoders[i]->height;
    if(w<=0||h<=0||w>4096||h>4096){ok=NO;why=@"Invalid video dimensions.";break;}
    inputs[i]=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:@{AVVideoCodecKey:AVVideoCodecTypeH264,AVVideoWidthKey:@(w),AVVideoHeightKey:@(h),AVVideoCompressionPropertiesKey:@{AVVideoAverageBitRateKey:@(1500000)}}];
    adaptor=[AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:inputs[i] sourcePixelBufferAttributes:@{(id)kCVPixelBufferPixelFormatTypeKey:@(kCVPixelFormatType_32BGRA),(id)kCVPixelBufferWidthKey:@(w),(id)kCVPixelBufferHeightKey:@(h)}];
   }else{
    int ch=decoders[i]->ch_layout.nb_channels,rate=decoders[i]->sample_rate;
    if(ch<1||ch>2||rate<8000||rate>96000){ok=NO;why=@"Unsupported audio format.";break;}
    inputs[i]=[AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:@{AVFormatIDKey:@(kAudioFormatMPEG4AAC),AVSampleRateKey:@(rate),AVNumberOfChannelsKey:@(ch),AVEncoderBitRateKey:@(160000)}];
    AudioStreamBasicDescription asbd={0};asbd.mSampleRate=rate;asbd.mFormatID=kAudioFormatLinearPCM;asbd.mFormatFlags=kAudioFormatFlagIsSignedInteger|kAudioFormatFlagIsPacked;asbd.mBitsPerChannel=16;asbd.mChannelsPerFrame=ch;asbd.mBytesPerFrame=2*ch;asbd.mBytesPerPacket=2*ch;asbd.mFramesPerPacket=1;
    if(CMAudioFormatDescriptionCreate(kCFAllocatorDefault,&asbd,0,NULL,0,NULL,NULL,(CMAudioFormatDescriptionRef*)&audioFormats[i])!=noErr){ok=NO;break;}
   }
   inputs[i].expectsMediaDataInRealTime=NO;
   if(![writer canAddInput:inputs[i]]){ok=NO;why=[NSString stringWithFormat:@"Cannot encode media track %u: %@",i,writer.error.localizedDescription?:@"Unsupported track settings"];break;}[writer addInput:inputs[i]];
  }
  if(ok&&((vi<0 && ![source.pathExtension.lowercaseString isEqualToString:@"adx"])||![writer startWriting])){ok=NO;why=writer.error.localizedDescription?:@"No video stream.";}
  if(ok)[writer startSessionAtSourceTime:kCMTimeZero];
  NSString *reasons[16]={nil};
  auto consume=[&](int i,AVFrame *frame)->BOOL{
   while(avcodec_receive_frame(decoders[i],frame)>=0){@autoreleasepool{
    AVAssetWriterInput *input=inputs[i];int waits=0;
    while(!input.readyForMoreMediaData){if(writer.status!=AVAssetWriterStatusWriting||++waits>15000){reasons[i]=[NSString stringWithFormat:@"Encoder wait failed on track %d (video %lld / audio %lld): %@",i,videoFrames,audioSamples[i],writer.error.localizedDescription?:@"input stalled"];return NO;}usleep(1000);}
    if(i==vi){
     CVPixelBufferRef pixel=NULL;if(CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault,adaptor.pixelBufferPool,&pixel)!=kCVReturnSuccess)return NO;
     CVPixelBufferLockBaseAddress(pixel,0);uint8_t *dst[4]={(uint8_t*)CVPixelBufferGetBaseAddress(pixel),NULL,NULL,NULL};int strides[4]={(int)CVPixelBufferGetBytesPerRow(pixel),0,0,0};
     scale=sws_getCachedContext(scale,frame->width,frame->height,(AVPixelFormat)frame->format,frame->width,frame->height,AV_PIX_FMT_BGRA,SWS_BILINEAR,NULL,NULL,NULL);
     if(!scale){CVPixelBufferUnlockBaseAddress(pixel,0);CVPixelBufferRelease(pixel);return NO;}
     sws_scale(scale,frame->data,frame->linesize,0,frame->height,dst,strides);CVPixelBufferUnlockBaseAddress(pixel,0);
     AVRational rate=format->streams[i]->avg_frame_rate;if(rate.num<=0)rate=format->streams[i]->r_frame_rate;if(rate.num<=0)rate={20,1};
     CMTime time=CMTimeMake(videoFrames++*(long long)rate.den,rate.num);
     BOOL appended=[adaptor appendPixelBuffer:pixel withPresentationTime:time];CVPixelBufferRelease(pixel);if(!appended)return NO;
    }else{
     int ch=decoders[i]->ch_layout.nb_channels,n=frame->nb_samples;size_t size=n*ch*2;NSMutableData *data=[NSMutableData dataWithLength:size];int16_t *pcm=(int16_t*)data.mutableBytes;
     if(frame->format==AV_SAMPLE_FMT_S16P){for(int j=0;j<n;j++)for(int c=0;c<ch;c++)pcm[j*ch+c]=((int16_t*)frame->extended_data[c])[j];}
     else if(frame->format==AV_SAMPLE_FMT_S16)memcpy(pcm,frame->data[0],size);else {reasons[i]=[NSString stringWithFormat:@"Unsupported decoded sample format: %d",frame->format];return NO;}
     CMBlockBufferRef block=NULL;CMSampleBufferRef sample=NULL;
     if(CMBlockBufferCreateWithMemoryBlock(kCFAllocatorDefault,NULL,size,kCFAllocatorDefault,NULL,0,size,0,&block)!=noErr)return NO;
     CMBlockBufferReplaceDataBytes(pcm,block,0,size);CMSampleTimingInfo timing={CMTimeMake(1,decoders[i]->sample_rate),CMTimeMake(audioSamples[i],decoders[i]->sample_rate),kCMTimeInvalid};size_t sampleSize=2*ch;
     OSStatus result=CMSampleBufferCreateReady(kCFAllocatorDefault,block,audioFormats[i],n,1,&timing,1,&sampleSize,&sample);CFRelease(block);
     if(result!=noErr){reasons[i]=[NSString stringWithFormat:@"Audio sample creation failed: %d",(int)result];return NO;}BOOL appended=[input appendSampleBuffer:sample];CFRelease(sample);audioSamples[i]+=n;if(!appended)return NO;
    }
    av_frame_unref(frame);
   }}return YES;
  };
  // USM may place long video runs before audio. Independent bounded readers let
  // AVAssetWriter interleave tracks without blocking the demuxer on video backpressure.
  std::atomic<bool> stopped(false);std::vector<std::thread> workers;
  if(ok)for(int i=0;i<16;i++)if(decoders[i])workers.emplace_back([&,i]{@autoreleasepool{
   AVFormatContext *reader=NULL;AVPacket *packet=av_packet_alloc();AVFrame *frame=av_frame_alloc();BOOL success=YES;
   if(avformat_open_input(&reader,source.fileSystemRepresentation,NULL,NULL)<0||avformat_find_stream_info(reader,NULL)<0){success=NO;reasons[i]=@"Cannot read media track.";}
   int readResult=0;
   while(success&&!stopped.load()&&(readResult=av_read_frame(reader,packet))>=0){
    if(packet->stream_index==i){
     int ret=avcodec_send_packet(decoders[i],packet);
     if(ret==AVERROR(EAGAIN)){success=consume(i,frame);if(success)ret=avcodec_send_packet(decoders[i],packet);}
     if(ret<0){char message[256];av_strerror(ret,message,sizeof(message));success=NO;reasons[i]=[NSString stringWithFormat:@"Decoder track %d: %s",i,message];}
     else if(!consume(i,frame))success=NO;
    }av_packet_unref(packet);
   }
   if(success&&!stopped.load()){avcodec_send_packet(decoders[i],NULL);success=consume(i,frame);}
   if(!success){stopped.store(true);if(!reasons[i])reasons[i]=writer.error.localizedDescription?:@"Media conversion failed.";}
   if(inputs[i])[inputs[i] markAsFinished];
   if(reader)avformat_close_input(&reader);av_frame_free(&frame);av_packet_free(&packet);
  }});
  for(auto &worker:workers)worker.join();
  if(stopped.load()){ok=NO;for(int i=0;i<16;i++)if(reasons[i]){why=reasons[i];break;}}
  if(ok){dispatch_semaphore_t done=dispatch_semaphore_create(0);[writer finishWritingWithCompletionHandler:^{dispatch_semaphore_signal(done);}];dispatch_semaphore_wait(done,DISPATCH_TIME_FOREVER);ok=writer.status==AVAssetWriterStatusCompleted;if(!ok)why=writer.error.localizedDescription;}
  else [writer cancelWriting];
  for(int i=0;i<16;i++){avcodec_free_context(&decoders[i]);if(audioFormats[i])CFRelease(audioFormats[i]);}sws_freeContext(scale);if(format)avformat_close_input(&format);
  if(!ok)[[NSFileManager defaultManager] removeItemAtPath:destination error:nil];return ok?YES:fail(error,why,writer.error ?: (error?*error:nil));
}
