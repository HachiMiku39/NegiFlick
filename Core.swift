import Foundation
import SwiftUI
import AVFoundation
import Combine

let teal = Color(red: 0.02, green: 0.69, blue: 0.70)
let backdrop = Color(red: 0.035, green: 0.07, blue: 0.11)
func traceMenuAudio(_ event:String){
 #if DEBUG
 print(String(format:"[MenuAudio %.3f] %@",ProcessInfo.processInfo.systemUptime,event))
 #endif
}
@MainActor final class Preferences: ObservableObject {
    static let shared = Preferences()
    let language: Language
    @Published var music: Double { didSet { save() } }
    @Published var sfx: Double { didSet { save() } }
    @Published var failSound: Bool { didSet { save() } }
    @Published var timingHints: Bool { didSet { save() } }
    @Published var roman: Bool { didSet { save() } }
    @Published var originalJudgements: Bool { didSet { save() } }
    @Published var developerEnabled: Bool { didSet { if !developerEnabled { autoplay = false; performanceHUD = false; metalHUD = false }; save() } }
    @Published var autoplay: Bool { didSet { save() } }
    @Published var performanceHUD: Bool { didSet { save() } }
    @Published var metalHUD: Bool { didSet { save() } }
    var effectivePerformanceHUD: Bool { developerEnabled && performanceHUD }
    var effectiveMetalHUD: Bool { developerEnabled && metalHUD }
    var effectiveAutoplay: Bool { developerEnabled && autoplay }
    var effectiveTimingHints: Bool { timingHints && !originalJudgements }
    init() {
        let d=UserDefaults.standard
        language = .system()
        originalJudgements=d.bool(forKey:"originalJudgements");developerEnabled=d.bool(forKey:"developerEnabled")
        autoplay=d.bool(forKey:"developerEnabled") && d.bool(forKey:"autoplay")
        performanceHUD=d.bool(forKey:"developerEnabled") && d.bool(forKey:"performanceHUD")
        metalHUD=d.bool(forKey:"developerEnabled") && d.bool(forKey:"metalHUD")
        music=d.object(forKey:"music") as? Double ?? 0.85; sfx=d.object(forKey:"sfx") as? Double ?? 0.75
        timingHints=d.bool(forKey:"timingHints"); failSound=d.object(forKey:"failSound") as? Bool ?? true; roman=d.bool(forKey:"roman")
    }
    private func save() { let d=UserDefaults.standard; d.set(music,forKey:"music"); d.set(sfx,forKey:"sfx"); d.set(failSound,forKey:"failSound"); d.set(roman,forKey:"roman"); d.set(timingHints,forKey:"timingHints"); d.set(originalJudgements,forKey:"originalJudgements"); d.set(developerEnabled,forKey:"developerEnabled"); d.set(autoplay,forKey:"autoplay"); d.set(performanceHUD,forKey:"performanceHUD"); d.set(metalHUD,forKey:"metalHUD"); d.set(effectiveMetalHUD,forKey:"MetalHUDForceEnabled") }
    func text(_ key:String)->String {UIStrings.text(key,language:language)}
}

func resource(_ name:String,_ ext:String)->URL? { Bundle.main.url(forResource:name,withExtension:ext,subdirectory:"GameAssets") }
private let originalImages:NSCache<NSString,UIImage> = {let cache=NSCache<NSString,UIImage>();cache.totalCostLimit=64*1024*1024;return cache}()
func originalImage(_ name:String)->UIImage? {
 if let cached=originalImages.object(forKey:name as NSString){return cached}
 let image=resource(name,"png").flatMap{UIImage(contentsOfFile:$0.path)} ?? NeutralArtwork.image(name)
 originalImages.setObject(image,forKey:name as NSString,cost:1024*1024)
 return image
}
func noteCharacterImage(_ glyph:NoteGlyph)->UIImage? {nil}
private let songTitleImages=NSCache<NSString,UIImage>()
func songTitleImage(_ url:URL)->UIImage? {
 if let cached=songTitleImages.object(forKey:url.path as NSString){return cached}
 guard let source=UIImage(contentsOfFile:url.path) else{return nil}
 let image=trimSongTitle(source);songTitleImages.setObject(image,forKey:url.path as NSString);return image
}
func trimSongTitle(_ image:UIImage)->UIImage {
 guard let source=image.cgImage else{return image}
 let width=source.width,height=source.height
 guard let context=CGContext(data:nil,width:width,height:height,bitsPerComponent:8,bytesPerRow:width*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),let bytes=context.data?.assumingMemoryBound(to:UInt8.self) else{return image}
 context.draw(source,in:CGRect(x:0,y:0,width:width,height:height))
 var left=width,right=0,top=height,bottom=0
 for y in 0..<height{for x in 0..<width where bytes[(y*width+x)*4+3]>1{left=min(left,x);right=max(right,x+1);top=min(top,y);bottom=max(bottom,y+1)}}
 guard right>left,bottom>top,let crop=context.makeImage()?.cropping(to:CGRect(x:left,y:top,width:right-left,height:bottom-top)) else{return image}
 return UIImage(cgImage:crop)
}
struct Song: Codable,Identifiable {
 let id:String; let title:String; let artist:String; let art:String; let eventCount:Int
 var folder:String?=nil; var movie:String?=nil; var chartPath:String?=nil; var artworkPath:String?=nil;var titleArtworkPath:String?=nil;var customMetadata:Metadata?=nil;var inputLanguage:NoteInputLanguage?=nil
 func installedURL(_ path:String)->URL { path.hasPrefix("/") ? URL(fileURLWithPath:path) : PackStore.installRoot.appendingPathComponent(path) }
 struct Metadata:Codable {let bpm:Int?;let levels:[Int?];let atlas:String?;let artworkIndex:Int?;let titleAsset:String?}
 static let metadata:[String:Metadata] = (try? resource("song-metadata","json").flatMap {try JSONDecoder().decode([String:Metadata].self,from:Data(contentsOf:$0))}) ?? [:]
 var metadata:Metadata? {customMetadata ?? Self.metadata[id.split(separator:".").last.map(String.init) ?? id]}
 func level(_ difficulty:Difficulty)->String {guard let levels=metadata?.levels,levels.indices.contains(difficulty.rawValue),let n=levels[difficulty.rawValue],n>0 else{return "—"};return String(n)}
 var movieURL:URL? { movie.map(installedURL) ?? resource(id,"mp4") }
 var chartURL:URL? { chartPath.map(installedURL) ?? resource(id,"json") }
 var titleImage:UIImage? {
  if let path=titleArtworkPath,let image=songTitleImage(installedURL(path)){return image}
  if folder==nil,let asset=metadata?.titleAsset,let url=resource(asset,"png"){return songTitleImage(url)}
  if let folder,let atlas=metadata?.atlas,let index=metadata?.artworkIndex{return legacySongLogo(installedURL(folder+"/"+atlas+".png"),index:index)}
  return nil
 }
 var image:UIImage? { artworkPath.flatMap { UIImage(contentsOfFile:installedURL($0).path) } ?? originalImage(art) }
}
func legacySongLogo(_ url:URL,index:Int)->UIImage? {
 guard (0...2).contains(index),let image=UIImage(contentsOfFile:url.path)?.cgImage else{return nil}
 // music_00_01.plist defines the shared artwork/title layout used by song packs.
 let frames=[CGRect(x:0,y:576,width:512,height:256),CGRect(x:319,y:0,width:512,height:256),CGRect(x:0,y:319,width:512,height:256)]
 let plist=url.deletingPathExtension().appendingPathExtension("plist")
 let frameName="logo_"+url.deletingPathExtension().lastPathComponent.replacingOccurrences(of:"music_",with:"")+String(format:"_%02d.png",index)
 var rect=frames[index]
 if let data=try? Data(contentsOf:plist),let table=(try? PropertyListSerialization.propertyList(from:data,format:nil)) as? [String:Any],let frames=table["frames"] as? [String:[String:Any]],let f=frames[frameName],let x=f["x"] as? Int,let y=f["y"] as? Int,let w=f["width"] as? Int,let h=f["height"] as? Int {rect=CGRect(x:x,y:y,width:w,height:h)}
 return image.cropping(to:rect).map{trimSongTitle(UIImage(cgImage:$0))}
}
struct GameRecord:Codable,Identifiable {
 let id:UUID;let songID:String;let title:String;let difficulty:Int;let date:Date;let tally:OriginalScore
 static var all:[GameRecord] {guard let data=UserDefaults.standard.data(forKey:"originalRules.v1.records"),let records=try? JSONDecoder().decode([GameRecord].self,from:data) else{return []};return records}
 static func bestRank(songID:String,difficulty:Difficulty)->String? {
  let saved=UserDefaults.standard.string(forKey:"originalRules.v1.rank.\(songID).\(difficulty.rawValue)")
  return BestRank.strongest(([saved].compactMap{$0})+all.filter{$0.songID==songID && $0.difficulty==difficulty.rawValue}.map{$0.tally.rank})
 }
 static func save(song:Song,difficulty:Difficulty,tally:OriginalScore) {
  if let rank=BestRank.strongest([bestRank(songID:song.id,difficulty:difficulty),tally.rank].compactMap{$0}){UserDefaults.standard.set(rank,forKey:"originalRules.v1.rank.\(song.id).\(difficulty.rawValue)")}
  var records=all;records.removeAll{$0.songID==song.id && $0.difficulty==difficulty.rawValue};records.insert(GameRecord(id:UUID(),songID:song.id,title:song.title,difficulty:difficulty.rawValue,date:Date(),tally:tally),at:0);if let data=try? JSONEncoder().encode(records){UserDefaults.standard.set(data,forKey:"originalRules.v1.records")}}
}
@MainActor final class SoundEffects:NSObject,AVAudioPlayerDelegate {
 static let shared=SoundEffects()
 private var voices:[AVAudioPlayer]=[]
 private var titleAnnouncementPlayed=false
 private var launchVoice:AVAudioPlayer?
 private var titleVoice:AVAudioPlayer?
 private var titleCompletion:(()->Void)?

 func playTitleAnnouncementOnce(completion:@escaping ()->Void){
  guard !titleAnnouncementPlayed else{completion();return}
  titleAnnouncementPlayed=true
  guard Preferences.shared.sfx>0,let url=resource("neutral-title","caf"),let audio=try? AVAudioPlayer(contentsOf:url) else{completion();return}
  titleVoice=audio;titleCompletion=completion;audio.delegate=self
  audio.volume=Float(Preferences.shared.sfx);audio.prepareToPlay()
  if audio.play(){traceMenuAudio(String(format:"TITLE START duration=%.3f",audio.duration))}else{finishTitleAnnouncement()}
 }
 private func finishTitleAnnouncement(){traceMenuAudio(String(format:"TITLE END position=%.3f duration=%.3f",titleVoice?.currentTime ?? 0,titleVoice?.duration ?? 0));let completion=titleCompletion;titleCompletion=nil;titleVoice?.stop();titleVoice=nil;completion?()}
 nonisolated func audioPlayerDidFinishPlaying(_ player:AVAudioPlayer,successfully flag:Bool){Task{@MainActor [weak self] in self?.finishTitleAnnouncement()}}
 nonisolated func audioPlayerDecodeErrorDidOccur(_ player:AVAudioPlayer,error:Error?){Task{@MainActor [weak self] in self?.finishTitleAnnouncement()}}
 func suspendTitleAnnouncement(){titleVoice?.pause()}
 func resumeTitleAnnouncement(){if titleCompletion != nil{titleVoice?.play()}}
 func playLaunchAnnouncement(){
  guard Preferences.shared.sfx>0,let url=resource("neutral-launch","caf"),let audio=try? AVAudioPlayer(contentsOf:url) else{return}
  try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.default)
  try? AVAudioSession.sharedInstance().setActive(true)
  launchVoice=audio;audio.volume=Float(Preferences.shared.sfx);audio.prepareToPlay();audio.play()
 }
 func stopLaunchAnnouncement(){launchVoice?.stop();launchVoice=nil}
    func play(_ name:String) {guard Preferences.shared.sfx>0,let u=resource(name,"caf"),let p=try? AVAudioPlayer(contentsOf:u) else{return};voices.removeAll {!$0.isPlaying};p.volume=Float(Preferences.shared.sfx);p.play();voices.append(p)}
}
// One looping player for menu music. Gameplay stops it before the movie starts.
@MainActor final class MenuMusic {
 static let shared=MenuMusic()
 private var player:AVAudioPlayer?;private var track:String?;private var volumeObserver:AnyCancellable?
 // Gate every menu-music entry point from launch, including the first-run tutorial.
 private var titleSequenceStarted=false;private var waitingForTitle=true
 private var pendingURL:URL?;private var suspended=false
 private init(){try? AVAudioSession.sharedInstance().setCategory(.playback,mode:.default);try? AVAudioSession.sharedInstance().setActive(true);volumeObserver=Preferences.shared.$music.sink{[weak self] value in self?.player?.volume=Float(value)}}
 func play(_ name:String){guard let url=resource(name,"caf") else{return};playURL(url)}
 func playHomeAfterTitle(){
  guard !titleSequenceStarted else{play("BGM01");return}
  titleSequenceStarted=true;stop();waitingForTitle=true;play("BGM01")
  SoundEffects.shared.playTitleAnnouncementOnce{[weak self] in
   guard let self else{return};self.waitingForTitle=false
   let next=self.pendingURL;self.pendingURL=nil
   if let next{self.playURL(next)}
  }
 }
 func playURL(_ url:URL){
  // Remember the current page's music if the user navigates during the announcement.
  guard !waitingForTitle else{traceMenuAudio("BGM DEFER "+url.lastPathComponent);pendingURL=url;return}
  let name=url.path;if track==name,let player{player.volume=Float(Preferences.shared.music);if !suspended && !player.isPlaying{player.play()};return}
  stop();guard let audio=try? AVAudioPlayer(contentsOf:url) else{return};track=name;player=audio;audio.numberOfLoops = -1;audio.volume=Float(Preferences.shared.music);audio.prepareToPlay();if !suspended && audio.play(){traceMenuAudio("BGM START "+url.lastPathComponent)}
 }
 func stop(){pendingURL=nil;player?.stop();player=nil;track=nil}
 func suspend(){suspended=true;player?.pause();SoundEffects.shared.suspendTitleAnnouncement()}
 func resume(){suspended=false;SoundEffects.shared.resumeTitleAnnouncement();if !waitingForTitle,let player{player.volume=Float(Preferences.shared.music);player.play()}}
}
@MainActor final class SongPreview {
 static let shared=SongPreview();private var generation=UUID();private var conversions:[String:Task<Bool,Never>]=[:]
 func stop(){generation=UUID();MenuMusic.shared.stop()}
 func play(_ song:Song){stop();let token=generation
  if let url=resource(song.id+".preview","m4a"){MenuMusic.shared.playURL(url);return}
  Task{guard let folder=song.folder,let entry=(try? resource("dlc-catalog","json").flatMap{try JSONDecoder().decode([CatalogEntry].self,from:Data(contentsOf:$0))})?.first(where:{$0.m_MovieDataFileName==song.id.split(separator:".").last.map(String.init)}),let name=entry.m_PreSoundFileName else{return}
   let source=song.installedURL(folder+"/"+name+".adx");let destination=song.installedURL(folder+"/Playback/"+name+".preview.caf")
   guard FileManager.default.fileExists(atPath:source.path) else{return}
   if conversions[destination.path] != nil || !FileManager.default.fileExists(atPath:destination.path){let job=conversions[destination.path] ?? Task.detached{var error:NSError?;return MFConvertUSM(source.path,destination.path,&error)};conversions[destination.path]=job;let converted=await job.value;conversions[destination.path]=nil;guard converted else{return}}
   guard token==generation else{return};MenuMusic.shared.playURL(destination)
  }
 }
}
// Translation lookup never replaces the Japanese chart cue.
protocol LyricsProvider {func translation(_ original:String)->String?}
struct LocalLyricsProvider:LyricsProvider {
 let language:Language;private let map:SubtitleMap
 let source:SubtitleTrack?
 init(song:Song,language:Language){
  self.language=language
  let base=String(song.id.split(separator:".").last ?? "")
  let names=Array(Set([song.id,base])).sorted{($0==song.id ? 0:1)<($1==song.id ? 0:1)}
  let candidates=names.map{SubtitleStore.root.appendingPathComponent("\($0).lyrics.\(language.rawValue).json")}+names.compactMap{name in song.folder.map{song.installedURL($0).appendingPathComponent("\(name).lyrics.\(language.rawValue).json")}}+names.compactMap{resource("\($0).lyrics.\(language.rawValue)","json")}
  var values:[String:String]=[:],credit:SubtitleTrack?
  if language != .ja {for url in candidates{guard let data=try? Data(contentsOf:url) else{continue};if let track=try? JSONDecoder().decode(SubtitleTrack.self,from:data),track.languageCode==language.rawValue{values=track.lines;credit=track;break};if let legacy=try? JSONDecoder().decode([String:String].self,from:data){values=legacy;break}}}
  map=SubtitleMap(values);source=credit
 }
 func translation(_ original:String)->String? {map.translation(for:original,language:language)}
}
@MainActor final class GameEngine:ObservableObject {
 let song:Song;let difficulty:Difficulty;let mode:PlayMode;let player=AVPlayer();let sfx=SoundEffects()
 @Published var clock=0.0;@Published var duration=1.0;@Published var score=0;@Published var combo=0;@Published var maxCombo=0;@Published var hits=0;@Published var misses=0
 @Published var tally=OriginalScore(totalNotes:0,totalInterlude:0,btl:false);@Published var timingHint="";
 @Published private(set) var effects:[GameplayEffect]=[]
 @Published private(set) var normalAlpha=0.0;@Published private(set) var interludeAlpha=0.0
 @Published var failedResult=false;@Published var newRecord=false
 @Published private(set) var inputTimingStep:Int
 @Published var judgement="";@Published var lyric="";@Published var paused=false;@Published var finished=false;@Published var error:String?;@Published var preparing=true;@Published var mini=false
 @Published private(set) var autoplay=false
 @Published private(set) var scrubbing=false
 private var resumeAfterScrub=false;private var seekToken=UUID()
 private var lyricsProvider:LocalLyricsProvider?
 var lyricTranslation:String? {translation(of:lyric)}
 var subtitleSource:SubtitleTrack? {lyricsProvider?.source}
 func translation(of original:String)->String? {lyricsProvider?.translation(original)}
 var notes:[Note]=[];var cues:[Cue]=[];var resolved:Set<Int>=[];private lazy var displayClock=PlaybackDisplayClock{[weak self] in guard let self else{return};self.tick(self.player.currentTime().seconds)};private var ending:NSObjectProtocol?;private var cueIndex=0
 private var transitions:[(Double,Bool)]=[];private var transitionIndex=0;private var generation=UUID()
 private var normalFade=OriginalUIFade();private var interludeFade=OriginalUIFade()
 private var exitingInterlude=false
 init(song:Song,difficulty:Difficulty,mode:PlayMode){self.song=song;self.difficulty=difficulty;self.mode=mode;inputTimingStep=min(10,max(-10,UserDefaults.standard.integer(forKey:"inputTiming.\(song.id)")))}
 func justTick(_ note:Note)->Int {OriginalRules.justTick(note,step:inputTimingStep)}
 var timingBPM:Int {notes.first(where:{$0.time>=clock})?.timingBPM ?? song.metadata?.bpm ?? 175}
 var inputTimingMS:Double {Double(OriginalRules.inputOffsetTicks(step:inputTimingStep,bpm:timingBPM))*1000/30}
 func setInputTiming(_ step:Int){inputTimingStep=min(10,max(-10,step));UserDefaults.standard.set(inputTimingStep,forKey:"inputTiming.\(song.id)")}
 var target:Note? {OriginalVisuals.target(notes:notes,resolved:resolved,interlude:mini)}
 var normalTarget:Note? {OriginalVisuals.target(notes:notes,resolved:resolved,interlude:false)}
 var guides:[PanelGuideHint] {OriginalVisuals.guides(notes:notes,resolved:resolved,time:clock,step:inputTimingStep)}
 var visible:[Note] {mode != .play ? [] : notes.filter{!resolved.contains($0.id) && OriginalRules.baseTick($0)<=OriginalRules.tick(clock) && Double(justTick($0))/30>=clock-0.4}}
 var bestKey:String {"originalRules.v1.best.\(song.id).\(difficulty.rawValue)"}
 func start() {
  stop();SongPreview.shared.stop();generation=UUID();let token=generation;preparing=true;finished=false;failedResult=false;newRecord=false;paused=false;error=nil;clock=0;score=0;combo=0;maxCombo=0;hits=0;misses=0;lyric="";resolved=[];effects=[];cueIndex=0;transitionIndex=0;mini=false;judgement="";timingHint=""
  normalFade=OriginalUIFade();interludeFade=OriginalUIFade();normalAlpha=0;interludeAlpha=0;exitingInterlude=false
  autoplay = mode == .play && Preferences.shared.effectiveAutoplay
  lyricsProvider=LocalLyricsProvider(song:song,language:Preferences.shared.language)
  Task { [self] in
   do {
    guard let u=song.chartURL,let media=song.movieURL else{throw CocoaError(.fileNoSuchFile)}
    let chart=try JSONDecoder().decode(Chart.self,from:Data(contentsOf:u));cues=chart.events.sorted{$0.time<$1.time};notes=ChartCompiler.notes(chart,difficulty);tally=OriginalScore(totalNotes:notes.filter{$0.playable && !$0.interlude}.count,totalInterlude:notes.filter{$0.playable && $0.interlude}.count,btl:difficulty == .breakLimit)
    var delay=1.7;transitions=[]
    for e in cues {
     let c=Array(e.parameter)
     if c.first=="7",let ms=Double(String(c.dropFirst())){delay=ms/1000}
     // EndInterludeMode holds interlude alpha for GetNoteDelay()/30 ticks before fading it out.
     if c.first=="5",c.count>=6,c[1+difficulty.rawValue]=="2" {transitions.append((e.time+Double(Int(delay*1000)/30)/30,false))}
    }
    transitions.sort{$0.0<$1.0}
    let asset=AVURLAsset(url:media);let length=try await asset.load(.duration);let video=try await asset.loadTracks(withMediaType:.video);let audio=try await asset.loadTracks(withMediaType:.audio)
    guard token==generation else{return};guard length.seconds.isFinite,length.seconds>0,!video.isEmpty else{throw CocoaError(.fileReadCorruptFile)}
    let composition=AVMutableComposition();let range=CMTimeRange(start:.zero,duration:length)
    if let v=video.first,let t=composition.addMutableTrack(withMediaType:.video,preferredTrackID:kCMPersistentTrackID_Invalid){try t.insertTimeRange(range,of:v,at:.zero)}
    let chosen=mode == .karaoke ? Array(audio.suffix(1)) : audio
    guard mode != .karaoke || audio.count>=2 else{throw CocoaError(.fileReadUnsupportedScheme)}
    for a in chosen {if let t=composition.addMutableTrack(withMediaType:.audio,preferredTrackID:kCMPersistentTrackID_Invalid){try t.insertTimeRange(range,of:a,at:.zero)}}
    try AVAudioSession.sharedInstance().setCategory(.playback,mode:.default);try AVAudioSession.sharedInstance().setActive(true)
    let item=AVPlayerItem(asset:composition);player.replaceCurrentItem(with:item);player.volume=Float(Preferences.shared.music);duration=length.seconds
    ending=NotificationCenter.default.addObserver(forName:.AVPlayerItemDidPlayToEndTime,object:item,queue:.main){[weak self] _ in MainActor.assumeIsolated{self?.complete()}}
    preparing=false;player.play();displayClock.setRunning(true)
   }catch{if token==generation{self.error=localizedUIError(error,media:true);preparing=false}}
  }
 }
 func tick(_ time:Double) {
  guard time.isFinite,!finished,!scrubbing,mode != .play || !paused else{return};clock=time
  if effects.contains(where:{time-$0.time>=20.0/30}){effects.removeAll{time-$0.time>=20.0/30}}
  if effects.last?.note.interlude != false{judgement="";timingHint=""}
  if player.currentItem?.status == .failed {error=localizedUIError(player.currentItem?.error ?? CocoaError(.fileReadCorruptFile),media:true);player.pause();displayClock.setRunning(false);return}
  while cueIndex<cues.count && cues[cueIndex].time<=time {
   let cue=cues[cueIndex],bytes=Array(cue.parameter)
   if bytes.first=="3" {lyric=String(bytes.dropFirst())}
   if mode == .play {
    if cue.parameter=="1"{normalFade.set(visible:true,time:cue.time)}
    if cue.parameter=="2"{normalFade.set(visible:false,time:cue.time)}
    if bytes.first=="5",bytes.count>=6 {
     if bytes[1+difficulty.rawValue]=="1" && !mini {mini=true;exitingInterlude=false;interludeFade.set(visible:true,time:cue.time);normalFade.set(visible:false,time:cue.time)}
    }
   }
   cueIndex+=1
  }
  if mode == .play {
   while transitionIndex<transitions.count && transitions[transitionIndex].0<=time {interludeFade.set(visible:false,time:transitions[transitionIndex].0);exitingInterlude=true;transitionIndex+=1}
   interludeAlpha=interludeFade.alpha(time:time)
   if exitingInterlude && interludeAlpha<=0 {mini=false;exitingInterlude=false;if cueIndex<cues.count-10{normalFade.set(visible:true,time:time)}}
   normalAlpha=normalFade.alpha(time:time)
   for n in notes where !n.playable && !resolved.contains(n.id) && time>=n.time {resolved.insert(n.id)}
   if autoplay {
    for n in AutoplayScheduler.due(notes:notes,resolved:resolved,time:time,step:inputTimingStep) {
     resolve(n,.cool,time:Double(justTick(n))/30)
    }
   }else{
    for n in notes where n.playable && !resolved.contains(n.id) && OriginalRules.tick(time)-justTick(n) >= (difficulty == .breakLimit ? 10:12) {
     resolve(n,.worst,time:time);if tally.gameOver {complete();break}
    }
   }
  }

 }
 func input(key:Int,direction:Int,down:Double?=nil) {
  guard mode == .play,!autoplay,!paused,!finished,!preparing else{return}
  let now=player.currentTime().seconds
  guard now.isFinite else{return}
  let currentTick=OriginalRules.tick(now)
  let latest=difficulty == .breakLimit ? 9:11
  guard let n=notes.first(where:{$0.playable && !resolved.contains($0.id) && $0.interlude == mini && currentTick>=justTick($0)-11 && currentTick<=justTick($0)+latest}) else{return}
  let result=OriginalRules.flick(just:justTick(n),down:OriginalRules.tick(down ?? now),up:OriginalRules.tick(now),boardMatches:n.interlude || n.key==key,directionMatches:n.interlude || n.direction==direction)
  guard result != .none else{return}
  resolve(n,result,time:now,manual:true)
  if tally.gameOver { complete() }
 }
 func resolve(_ note:Note,_ result:Judgement,time:Double,manual:Bool=false) {
  guard resolved.insert(note.id).inserted else{return}
  tally.apply(result,interlude:note.interlude,crimax:note.crimax)
  score=tally.total;combo=tally.combo;maxCombo=tally.maxCombo
  hits=tally.counts[3]+tally.counts[4]+tally.counts[5];misses=tally.counts[1]
  if !(tally.btl && (result == .sad || result == .worst)) && (!note.interlude || result.rawValue >= Judgement.fine.rawValue) {judgement=result.label}
  let delta=OriginalRules.tick(time)-justTick(note)
  timingHint = autoplay || result == .worst || judgement.isEmpty || delta == 0 ? "" : delta<0 ? "FAST":"LATE"
  let suppressed=tally.btl && (result == .sad || result == .worst)
  if !suppressed && (!note.interlude || result.rawValue>=Judgement.fine.rawValue) {
   effects.append(GameplayEffect(id:note.id,time:time,note:note,result:result,pulse:manual || autoplay,combo:combo,timingHint:timingHint))
   // Rapid dense charts may resolve many notes between display callbacks.
   effects=Array(effects.filter{time-$0.time<20.0/30}.suffix(24))
  }
  player.volume=Float(Preferences.shared.music * (tally.btl ? 1:min(1,tally.gauge/128+0.35)))
  if result.rawValue>=Judgement.fine.rawValue {
   sfx.play(note.interlude ? "SE04":note.crimax && result == .cool && combo>=100 ? "SE01":"SE02")
   if note.interlude && tally.interludeSuccess==tally.totalInterlude {sfx.play("SE02")}
   if manual {UIImpactFeedbackGenerator(style:.light).impactOccurred()}
  }else if result == .safe && !note.interlude{sfx.play("SE01_03")}
  else if Preferences.shared.failSound && !note.interlude{sfx.play(result == .sad ? "SE03":"SE04v2")}
 }
 func togglePause(){guard !finished,!preparing,!scrubbing else{return};paused.toggle();if paused{player.pause();displayClock.setRunning(false)}else{sfx.play("SE09");if mode != .play && clock>=duration-0.02{complete()}else{player.play();displayClock.setRunning(true)}}}
 func pause(){if !paused && !finished && !preparing{paused=true;player.pause();displayClock.setRunning(false)}}
 func beginScrubbing(){guard mode != .play,!preparing,!finished,!scrubbing else{return};resumeAfterScrub = !paused;scrubbing=true;player.pause();displayClock.setRunning(false)}
 func endScrubbing(at seconds:Double){
  guard scrubbing,seconds.isFinite else{return}
  let destination=min(duration,max(0,seconds)),token=UUID(),session=generation
  seekToken=token
  player.seek(to:CMTime(seconds:destination,preferredTimescale:600),toleranceBefore:.zero,toleranceAfter:.zero){[weak self] completed in
   Task{@MainActor in
    guard let self,self.generation==session,self.seekToken==token else{return}
    self.scrubbing=false
    // Replay only lyric cues after a backward seek. Rhythm gameplay cannot seek.
    self.cueIndex=0;self.lyric=""
    self.tick(self.player.currentTime().seconds)
    if self.resumeAfterScrub && !self.paused {
     if completed && destination>=self.duration-0.02{self.complete()}else{self.player.play();self.displayClock.setRunning(true)}
    }
   }
  }
 }
 func complete(){
  guard !finished,!scrubbing else{return}
  if mode == .play {
   if !tally.gameOver {for n in notes where n.playable && !resolved.contains(n.id){resolve(n,autoplay ? .cool:.worst,time:clock)}}
   if !autoplay {let previous=UserDefaults.standard.integer(forKey:bestKey);newRecord=score>previous
   UserDefaults.standard.set(max(score,previous),forKey:bestKey);GameRecord.save(song:song,difficulty:difficulty,tally:tally)}
  }
  finished=true;mini=false;player.pause();displayClock.setRunning(false)
  if mode == .play {
   MenuMusic.shared.play("BGM05")
   sfx.play("SE05_01")
   let rankSound=["Perfect!":"SE14","S":"SE13","A":"SE12","B":"SE12","C":"SE12","D":"SE11","E":"SE11"][tally.rank]
   if let rankSound {let token=generation;Task{[weak self] in try? await Task.sleep(for:.milliseconds(650));guard let self,self.generation==token,self.finished else{return};self.failedResult=["D","E"].contains(self.tally.rank);self.sfx.play(rankSound)}}
  }
 }
 func stop(){generation=UUID();seekToken=UUID();scrubbing=false;resumeAfterScrub=false;effects=[];player.pause();displayClock.setRunning(false);if let ending{NotificationCenter.default.removeObserver(ending);self.ending=nil};player.replaceCurrentItem(with:nil)}
}

@MainActor func localizedUIError(_ error:Error,media:Bool=false)->String {
 let e=error as NSError
 let key:String
 if e.domain=="MikuPack"{key=[1:"errorPackFolders",2:"errorPackMovies",3:"errorVerification"][e.code] ?? "errorImport"}
 else if e.domain==NSCocoaErrorDomain {
  switch e.code {
  case NSFileNoSuchFileError,NSFileReadNoSuchFileError:key="errorFileMissing"
  case NSFileReadNoPermissionError,NSFileWriteNoPermissionError:key="errorAccess"
  case NSFileReadUnsupportedSchemeError:key=media ? "errorAudio":"errorFileRead"
  default:key="errorFileRead"
  }
 }else{key=media ? "errorMedia":"errorImport"}
 return Preferences.shared.text(key)
}

// Every built-in texture is rendered from these independent geometric primitives.
// Identifiers also serve legacy-compatible layout code; no original atlas is loaded.
enum NeutralArtwork {
 static let mint=UIColor(red:0.40,green:0.89,blue:0.69,alpha:1)
 static let ink=UIColor(red:0.08,green:0.15,blue:0.18,alpha:1)
 static func image(_ name:String)->UIImage {
  let wide=name.hasPrefix("menubutton_l") || name.hasPrefix("modechange") || name.hasPrefix("textbar") || name.hasPrefix("rail") || name=="difficultycursor" || name=="difficultycursor_break"
  let size=CGSize(width:wide ? 640:256,height:wide ? 128:256)
  let format=UIGraphicsImageRendererFormat();format.scale=1
  return UIGraphicsImageRenderer(size:size,format:format).image{ctx in
   let c=ctx.cgContext,rect=CGRect(origin:.zero,size:size),edge=min(size.width,size.height)
   func panel(_ fill:UIColor=ink,_ stroke:UIColor=mint){fill.setFill();stroke.setStroke();let p=UIBezierPath(roundedRect:rect.insetBy(dx:4,dy:4),cornerRadius:edge*0.14);p.lineWidth=3;p.fill();p.stroke()}
   func text(_ value:String,_ fraction:CGFloat=0.35,_ color:UIColor = .white){let font=UIFont.systemFont(ofSize:edge*fraction,weight:.semibold);let attrs:[NSAttributedString.Key:Any]=[.font:font,.foregroundColor:color];let bounds=(value as NSString).size(withAttributes:attrs);(value as NSString).draw(at:CGPoint(x:(size.width-bounds.width)/2,y:(size.height-bounds.height)/2),withAttributes:attrs)}
   func symbol(_ value:String,_ color:UIColor=mint){UIImage(systemName:value)?.withTintColor(color,renderingMode:.alwaysOriginal).draw(in:rect.insetBy(dx:edge*0.18,dy:edge*0.18))}
   if name.hasPrefix("bg_"){ink.setFill();c.fill(rect);return}
   if name.hasPrefix("rail"){
    ink.withAlphaComponent(0.75).setFill();c.fill(rect)
    for i in 0..<5{let color=name=="rail_01" ? UIColor(hue:CGFloat(i)/5,saturation:0.65,brightness:0.9,alpha:0.65):mint.withAlphaComponent(0.24);color.setStroke();c.setLineWidth(2);c.move(to:CGPoint(x:0,y:CGFloat(i+1)*size.height/6));c.addLine(to:CGPoint(x:size.width,y:CGFloat(i+1)*size.height/6));c.strokePath()};return
   }
   if name.hasPrefix("flickpanel_"){
    let active=name.contains("_on_"),index=Int(name.suffix(2)) ?? 0
    panel(active ? mint.withAlphaComponent(0.36):ink)
    let group=Array(kanaGroups[min(index,9)]).map(String.init)
    let full=name.contains("_fro_"),support=name.contains("_rah_")
    text(full ? roman(group[0]).uppercased():group[0],full ? 0.30:0.46)
    let positions=[CGPoint(x:0.17,y:0.5),CGPoint(x:0.5,y:0.17),CGPoint(x:0.83,y:0.5),CGPoint(x:0.5,y:0.83)]
    for i in 1..<group.count where !"（）".contains(group[i]){let label=full ? roman(group[i]):group[i];let attrs:[NSAttributedString.Key:Any]=[.font:UIFont.systemFont(ofSize:edge*0.13,weight:.medium),.foregroundColor:mint.withAlphaComponent(0.7)];let bounds=(label as NSString).size(withAttributes:attrs);let pos=positions[i-1];(label as NSString).draw(at:CGPoint(x:pos.x*edge-bounds.width/2,y:pos.y*edge-bounds.height/2),withAttributes:attrs)}
    if support{let label=roman(group[0]).uppercased();(label as NSString).draw(at:CGPoint(x:edge*0.66,y:edge*0.75),withAttributes:[.font:UIFont.systemFont(ofSize:edge*0.12),.foregroundColor:UIColor.white])};return
   }
   if name.contains("cursor"){mint.setStroke();let p=UIBezierPath(roundedRect:rect.insetBy(dx:4,dy:4),cornerRadius:edge*0.14);p.lineWidth=7;p.stroke();return}
   if name.hasPrefix("guidepanel_") || name.hasPrefix("inputguide_"){
    let index=Int(name.suffix(2)) ?? 0;symbol(["circle.fill","arrow.up","arrow.down","arrow.left","arrow.right"][min(index,4)],name.contains("_off") ? mint.withAlphaComponent(0.4):mint);return
   }
   if name.hasPrefix("charactercircle") || name=="ripple" || name.contains("whirl"){
    mint.withAlphaComponent(0.8).setStroke();let p=UIBezierPath(ovalIn:rect.insetBy(dx:8,dy:8));p.lineWidth=name.contains("whirl") ? 12:5
    if name.contains("whirl"){let d:[CGFloat]=[30,14];p.setLineDash(d,count:2,phase:0)};p.stroke();return
   }
   if name.hasPrefix("fireworks_"){
    mint.setStroke();c.setLineWidth(5);for i in 0..<20{let a=CGFloat(i)*CGFloat.pi/10;c.move(to:CGPoint(x:128+cos(a)*70,y:128+sin(a)*70));c.addLine(to:CGPoint(x:128+cos(a)*120,y:128+sin(a)*120));c.strokePath()};return
   }
   if name.hasPrefix("afterimage_"){
    let index=Int(name.suffix(2)) ?? 0;let colors:[UIColor]=[mint,.cyan,.blue,.orange,.purple];colors[min(index,4)].withAlphaComponent(0.7).setFill();let p=UIBezierPath();for i in 0..<5{let a=CGFloat(i)*CGFloat.pi*2/5-CGFloat.pi/2;let point=CGPoint(x:128+cos(a)*112,y:128+sin(a)*112);if i==0{p.move(to:point)}else{p.addLine(to:point)}};p.close();p.fill();return
   }
   if name.hasPrefix("evaluation_"){let index=Int(name.suffix(2)) ?? 0;text(["COOL","FINE","SAFE","SAD","WORST"][min(index,4)],0.19);return}
   if name.hasPrefix("quaver_"){symbol("music.note");return}
   if name.hasPrefix("flickguide_int"){panel(name.hasSuffix("on") ? mint:ink);text("TAP",0.27);return}
   if name.hasPrefix("flickguide_"){panel();return}
   if name.hasPrefix("menubutton_"){panel();return}
   if name.hasPrefix("modechange"){panel();text(name.hasSuffix("on") ? "BTL":"MODE CHANGE",0.38);return}
   if name.hasPrefix("clearrank_"){
    if name.hasSuffix("star"){symbol("star.fill")}else{let ranks=["S","A","B","C","D","E"];let n=Int(name.suffix(2));text(n.map{ranks[min($0,5)]} ?? String(name.suffix(1)).uppercased(),0.65,mint)};return
   }
   if name=="perfect"{text("AP",0.6,mint);return}
   if name.hasPrefix("difficulty"){symbol("star.fill");return}
   if name=="failed"{text("FAILED",0.22,.systemRed);return}
   if name=="newrecord"{text("BEST",0.20,.systemYellow);return}
   if name.hasPrefix("volumemeter"){panel(name.hasSuffix("on") ? mint:ink);return}
   if name=="textbar_00" || name=="volumewindow"{panel(ink.withAlphaComponent(0.65),mint.withAlphaComponent(0.22));return}
   if name.hasPrefix("keyboard_"){panel();symbol("keyboard");return}
   if name.hasPrefix("failedsound_") || name.hasPrefix("flowet_") || name.hasPrefix("panel_"){panel();text(name.contains("_on_") ? "ON":"OFF",0.27);return}
   if name.hasPrefix("lefthand") || name.hasPrefix("righthand"){panel();symbol(name.hasPrefix("lefthand") ? "hand.point.left.fill":"hand.point.right.fill");return}
   let symbols:[String:String]=["pausebutton":"pause.fill","speaker":"speaker.wave.2.fill","back":"arrow.left","home":"house.fill","playlist":"list.bullet","loop":"repeat","lyrics":"text.alignleft","karaoke":"mic.fill","shuffle":"shuffle","play":"play.fill","crownicon":"chart.bar","infoicon":"info.circle"]
   if let key=symbols.keys.sorted().first(where:{name.hasPrefix($0)}),let icon=symbols[key]{symbol(icon,name.hasSuffix("off") ? mint.withAlphaComponent(0.45):mint);return}
   // A neutral cover remains useful when an imported pack has no artwork.
   panel();symbol("waveform");
  }
 }
}
