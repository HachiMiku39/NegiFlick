import Foundation
import Combine
import UIKit
import AVFoundation

struct CatalogEntry:Decodable {let m_Title:String;let m_Artist:String?;let m_MovieDataFileName:String;let m_ArtWorkFileName:String;let m_ArtWorkIndex:Int;let m_PreSoundFileName:String?;let packID:Int}
enum SubtitleStore {
 static var root:URL {FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0].appendingPathComponent("LyricTranslations",isDirectory:true)}
 static func importFile(_ url:URL,songs:[Song])throws->Int {
  let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
  let data=try Data(contentsOf:url);guard data.count<=5*1024*1024 else{throw SubtitleError.invalid}
  let document=try JSONDecoder().decode(SubtitleDocument.self,from:data)
  try document.validate(songIDs:Set(songs.flatMap{[$0.id,String($0.id.split(separator:".").last ?? "")]}))
  try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
  for track in document.translations{let file=root.appendingPathComponent("\(track.songID).lyrics.\(track.languageCode!).json");try JSONEncoder().encode(track).write(to:file,options:.atomic)}
  return document.translations.count
 }
}
@MainActor final class PackStore:ObservableObject {
 @Published var songs:[Song]=[];@Published var installing=false;@Published var progress="";@Published var message:String?;@Published var failed=false
 nonisolated static var installRoot:URL {FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0].appendingPathComponent("InstallData",isDirectory:true)}
 init(){
  reload()
  #if DEBUG
  // Development-only harness exercises the real importer without bundling test media.
  let arguments=ProcessInfo.processInfo.arguments
  if let index=arguments.firstIndex(of:"--import-pack"),arguments.indices.contains(index+1){importResource(URL(fileURLWithPath:arguments[index+1]))}
  #endif
 }
 func reload() {
  var result=(try? resource("songs","json").flatMap{try JSONDecoder().decode([Song].self,from:Data(contentsOf:$0))}) ?? []
  if let dirs=try? FileManager.default.contentsOfDirectory(at:Self.installRoot,includingPropertiesForKeys:nil){for folder in dirs.sorted(by:{$0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending}) {let manifest=folder.appendingPathComponent("miku64-songs.json");if let data=try? Data(contentsOf:manifest),let items=try? JSONDecoder().decode([Song].self,from:data){result.append(contentsOf:items)}}};songs=result
 }
 func importArchive(_ url:URL) { importResource(url) }
 func importFolder(_ url:URL) { importResource(url) }
 private func importResource(_ url:URL) {
  guard !installing else{return};installing=true;failed=false;message=nil;progress=Preferences.shared.text("importing")
  Task {
   do {
    try await Task.detached(priority:.userInitiated){try await Self.install(url){stage,current,total in
     Task{@MainActor [weak self] in guard let self,self.installing else{return};let label=Preferences.shared.text(stage);self.progress=stage == "convertingSong" ? String(format:label,current,total):label}
    }}.value
    reload();message=Preferences.shared.text("importSuccess");NSLog("NegiFlick import completed: %@; songs=%ld",url.lastPathComponent,songs.count)
   }catch{failed=true;message=Preferences.shared.text("importFailed")+"\n"+localizedUIError(error)+"\n"+Self.importDetails(error)}
   installing=false;progress=""
  }
 }
 nonisolated private static func importDetails(_ error:Error)->String {
  let e=error as NSError
  var details=[e.userInfo["ImportStage"] as? String,e.userInfo["ImportFile"] as? String].compactMap{$0}
  var cause:NSError?=e
  for _ in 0..<5 {guard let current=cause else{break};details.append("\(current.domain) (\(current.code)): \(current.localizedDescription)");cause=current.userInfo[NSUnderlyingErrorKey] as? NSError}
  return details.joined(separator:"\n")
 }
 nonisolated private static func install(_ url:URL,report:@escaping @Sendable(String,Int,Int)->Void)async throws {
  var operation="Prepare",filename=url.lastPathComponent
  do {
  let access=url.startAccessingSecurityScopedResource();defer{if access{url.stopAccessingSecurityScopedResource()}}
  let fm=FileManager.default,root=installRoot;let stage=fm.temporaryDirectory.appendingPathComponent("MikuPack-"+UUID().uuidString,isDirectory:true)
  try fm.createDirectory(at:stage,withIntermediateDirectories:true);defer{try? fm.removeItem(at:stage)}
  var nativeError:NSError?
  if (try url.resourceValues(forKeys:[.isDirectoryKey])).isDirectory==true {
   operation="Copy";report("copyingPack",0,0)
   var coordinationError:NSError?,copyError:Error?
   NSFileCoordinator().coordinate(readingItemAt:url,options:[],error:&coordinationError){source in
    do {
     if let manifest=try customManifest(in:source){
      let data=try Data(contentsOf:manifest);guard data.count<=1024*1024 else{throw ChartPackageError.invalid("Manifest too large")}
      let package=try JSONDecoder().decode(CustomPackManifest.self,from:data);try package.validate()
      let sourceRoot=manifest.deletingLastPathComponent()
      try data.write(to:stage.appendingPathComponent("negiflick-pack.json"))
      for path in package.paths {let asset=try CustomPackManifest.asset(path,in:sourceRoot);let target=stage.appendingPathComponent(path);try fm.createDirectory(at:target.deletingLastPathComponent(),withIntermediateDirectories:true);try fm.copyItem(at:asset,to:target)}
     }else{
     var sources:[URL]=[]
     if source.lastPathComponent.range(of:"^(Mov|Thum)_[0-9]+$",options:.regularExpression) != nil{sources=[source]}
     else if let walk=fm.enumerator(at:source,includingPropertiesForKeys:[.isDirectoryKey],options:[.skipsHiddenFiles]){
      for case let folder as URL in walk where folder.lastPathComponent.range(of:"^(Mov|Thum)_[0-9]+$",options:.regularExpression) != nil {
       if (try folder.resourceValues(forKeys:[.isDirectoryKey])).isDirectory==true{sources.append(folder);walk.skipDescendants()}
      }
     }
     guard Set(sources.map(\.lastPathComponent)).count==sources.count else{throw CocoaError(.fileReadCorruptFile)}
     for source in sources{try fm.copyItem(at:source,to:stage.appendingPathComponent(source.lastPathComponent))}
     if sources.isEmpty{_ = try stageInitialPack(from:source,in:stage)}
     }
    }catch{copyError=error}
   }
   if let error=coordinationError ?? copyError as NSError?{throw error}
  }else{
   operation="Extract";report("extractingPack",0,0)
   guard MFExtractArchive(url.path,stage.path,&nativeError) else{throw nativeError ?? CocoaError(.fileReadCorruptFile) as NSError}
  }
  if let manifest=try customManifest(in:stage){operation="Install custom chart";try await installCustom(manifest,report:report);return}
  // Initial songs live flat inside the original App, unlike downloadable Mov_* packs.
  // Normalize only the known initial songs and their artwork; never copy or execute an App binary.
  _ = try stageInitialPack(from:stage,in:stage)
  guard let walk=fm.enumerator(at:stage,includingPropertiesForKeys:[.isDirectoryKey]) else{throw CocoaError(.fileReadCorruptFile)}
  var folders:[URL]=[]
  for case let path as URL in walk {
   let n=path.lastPathComponent
   if n.range(of:"^(Mov|Thum)_[0-9]+$",options:.regularExpression) != nil,(try? path.resourceValues(forKeys:[.isDirectoryKey]).isDirectory)==true {folders.append(path);walk.skipDescendants()}
  }
  guard Set(folders.map{$0.lastPathComponent}).count==folders.count else{throw CocoaError(.fileReadCorruptFile)}
  guard !folders.isEmpty else{throw NSError(domain:"MikuPack",code:1,userInfo:[NSLocalizedDescriptionKey:"No Mov_* folders or original initial-song USM files found."])}
  guard folders.contains(where:{$0.lastPathComponent.hasPrefix("Mov_")}) else{throw NSError(domain:"MikuPack",code:2,userInfo:[NSLocalizedDescriptionKey:"This pack contains no playable USM files."])}
  let catalog:[CatalogEntry]=try resource("dlc-catalog","json").map {try JSONDecoder().decode([CatalogEntry].self,from:Data(contentsOf:$0))} ?? []
  try fm.createDirectory(at:root,withIntermediateDirectories:true)
  for folder in folders where folder.lastPathComponent.hasPrefix("Mov_") {
   let pack=Int(folder.lastPathComponent.dropFirst(4)) ?? -1;var registered:[Song]=[]
   let files=try fm.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil)
   operation="Verify";filename=folder.lastPathComponent;report("verifyingPack",0,0);try verifyManifest(folder)
   let movies=files.filter({$0.pathExtension.lowercased()=="usm"}).sorted(by:{$0.lastPathComponent<$1.lastPathComponent})
   for (index,movie) in movies.enumerated() {
    report("convertingSong",index+1,movies.count)
    operation="Read chart";filename=movie.lastPathComponent
    let name=movie.deletingPathExtension().lastPathComponent;var chart=try UTFTable.chart(movie);chart.inputLanguage = .japanese;let playback=folder.appendingPathComponent("Playback",isDirectory:true);try fm.createDirectory(at:playback,withIntermediateDirectories:true)
    let dest=playback.appendingPathComponent(name+".mp4");nativeError=nil;operation="Convert media";guard MFConvertUSM(movie.path,dest.path,&nativeError) else{throw nativeError ?? CocoaError(.fileReadCorruptFile) as NSError}
    operation="Write song"
    let json=playback.appendingPathComponent(name+".json");try JSONEncoder().encode(chart).write(to:json,options:.atomic)
    let meta=catalog.first{$0.packID==pack && $0.m_MovieDataFileName==name}
    var artwork:String?;var titleArtwork:String?
    if let meta,let img=UIImage(contentsOfFile:folder.appendingPathComponent(meta.m_ArtWorkFileName+".png").path)?.cgImage {
     let rect=[CGRect(x:513,y:576,width:318,height:318),CGRect(x:513,y:257,width:318,height:318),CGRect(x:0,y:0,width:318,height:318)][max(0,min(meta.m_ArtWorkIndex,2))]
     if let cropped=img.cropping(to:rect),let png=UIImage(cgImage:cropped).pngData(){let local=playback.appendingPathComponent(name+".png");try png.write(to:local);artwork=folder.lastPathComponent+"/Playback/"+name+".png"}
    }
    if let meta,let logo=legacySongLogo(folder.appendingPathComponent(meta.m_ArtWorkFileName+".png"),index:meta.m_ArtWorkIndex),let png=logo.pngData(){let local=playback.appendingPathComponent(name+".title.png");try png.write(to:local);titleArtwork=folder.lastPathComponent+"/Playback/"+name+".title.png"}
    registered.append(Song(id:"pack\(pack).\(name)",title:meta?.m_Title ?? name.replacingOccurrences(of:"_",with:" "),artist:meta?.m_Artist ?? "",art:"",eventCount:chart.events.count,folder:folder.lastPathComponent,movie:folder.lastPathComponent+"/Playback/"+name+".mp4",chartPath:folder.lastPathComponent+"/Playback/"+name+".json",artworkPath:artwork,titleArtworkPath:titleArtwork,inputLanguage:.japanese))
   }
   guard !registered.isEmpty else{throw NSError(domain:"MikuPack",code:2,userInfo:[NSLocalizedDescriptionKey:"This pack contains no playable USM files."])}
   try JSONEncoder().encode(registered).write(to:folder.appendingPathComponent("miku64-songs.json"),options:.atomic)
  }
  // Commit only after every song converted successfully. Existing folders are retained as rollback backups.
  operation="Install";filename=url.lastPathComponent;report("registeringPack",0,0)
  let backup=root.deletingLastPathComponent().appendingPathComponent("ImportBackups/"+UUID().uuidString);var committed:[URL]=[];var previous:[(URL,URL)]=[]
  do {
   for folder in folders {let dest=root.appendingPathComponent(folder.lastPathComponent)
    if fm.fileExists(atPath:dest.path){try fm.createDirectory(at:backup,withIntermediateDirectories:true);let old=backup.appendingPathComponent(folder.lastPathComponent);try fm.moveItem(at:dest,to:old);previous.append((old,dest))}
    try fm.moveItem(at:folder,to:dest);committed.append(dest)
   }
  }catch{for dest in committed{try? fm.removeItem(at:dest)};for(old,dest) in previous{try? fm.moveItem(at:old,to:dest)};throw error}
  }catch{
   let original=error as NSError;var info=original.userInfo;info["ImportStage"]=operation;info["ImportFile"]=filename
   let detailed=NSError(domain:original.domain,code:original.code,userInfo:info)
   NSLog("NegiFlick import failed: %@",importDetails(detailed));throw detailed
  }
 }
 nonisolated private static func stageInitialPack(from source:URL,in stage:URL)throws->Bool {
  let fm=FileManager.default,dest=stage.appendingPathComponent("Mov_0",isDirectory:true)
  if fm.fileExists(atPath:dest.path){return false}
  let catalog:[CatalogEntry]=try resource("dlc-catalog","json").map{try JSONDecoder().decode([CatalogEntry].self,from:Data(contentsOf:$0))} ?? []
  let initial=catalog.filter{$0.packID==0},names=Set(initial.map{$0.m_MovieDataFileName+".usm"})
  guard !names.isEmpty,let walk=fm.enumerator(at:source,includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles]) else{return false}
  var movies:[String:URL]=[:]
  for case let file as URL in walk {
   if file.lastPathComponent.range(of:"^(Mov|Thum)_[0-9]+$",options:.regularExpression) != nil{walk.skipDescendants();continue}
   if names.contains(file.lastPathComponent),(try file.resourceValues(forKeys:[.isRegularFileKey])).isRegularFile==true {
    guard movies[file.lastPathComponent]==nil else{throw ChartPackageError.invalid("Duplicate initial song: "+file.lastPathComponent)}
    movies[file.lastPathComponent]=file
   }
  }
  guard !movies.isEmpty else{return false}
  try fm.createDirectory(at:dest,withIntermediateDirectories:true)
  for name in movies.keys.sorted(){guard let movie=movies[name] else{continue};try fm.copyItem(at:movie,to:dest.appendingPathComponent(name))
   guard let meta=initial.first(where:{$0.m_MovieDataFileName+".usm"==name}) else{continue}
   for ext in ["png","plist"] {
    let asset=movie.deletingLastPathComponent().appendingPathComponent(meta.m_ArtWorkFileName+"."+ext),target=dest.appendingPathComponent(asset.lastPathComponent)
    if fm.fileExists(atPath:asset.path),!fm.fileExists(atPath:target.path){try fm.copyItem(at:asset,to:target)}
   }
  }
  return true
 }
 nonisolated private static func verifyManifest(_ folder:URL)throws {
  let u=folder.appendingPathComponent("verificationFile.dat");guard let data=try? Data(contentsOf:u),let text=String(data:data,encoding:.utf8) else{return}
  for line in text.components(separatedBy:.newlines) {
   let parts=line.split(whereSeparator:{$0.isWhitespace});guard parts.count>=2,parts[0].count==40,parts[0].allSatisfy({$0.isHexDigit}) else{continue}
   let name=parts.dropFirst().joined(separator:" ");guard !name.contains("/"),!name.contains("\\"),name != ".." else{throw CocoaError(.fileReadCorruptFile)}
   let file=folder.appendingPathComponent(name)
   let reader=try FileHandle(forReadingFrom:file);defer{try? reader.close()};var digest=Insecure.SHA1()
   while let chunk=try reader.read(upToCount:262144),!chunk.isEmpty{digest.update(data:chunk)}
   let hash=digest.finalize().map{String(format:"%02x",$0)}.joined();guard hash==parts[0].lowercased() else{throw NSError(domain:"MikuPack",code:3,userInfo:[NSLocalizedDescriptionKey:"Verification failed: "+name])}
  }
 }
}
import CryptoKit

extension PackStore {
 nonisolated private static func customManifest(in folder:URL)throws->URL? {
  let fm=FileManager.default
  var found:[URL]=[]
  if let walk=fm.enumerator(at:folder,includingPropertiesForKeys:[.isRegularFileKey],options:[.skipsHiddenFiles]){
   for case let file as URL in walk where file.lastPathComponent=="negiflick-pack.json" {found.append(file);guard found.count<=1 else{throw ChartPackageError.invalid("A custom archive must contain one manifest")}}
  }
  return found.first
 }
 nonisolated private static func installCustom(_ manifest:URL,report:@escaping @Sendable(String,Int,Int)->Void)async throws {
  let data=try Data(contentsOf:manifest);guard data.count<=1024*1024 else{throw ChartPackageError.invalid("Manifest too large")}
  let package=try JSONDecoder().decode(CustomPackManifest.self,from:data);try package.validate()
  let source=manifest.deletingLastPathComponent(),fm=FileManager.default
  for path in package.paths{_ = try CustomPackManifest.asset(path,in:source)}
  let media=try CustomPackManifest.asset(package.media,in:source),asset=AVURLAsset(url:media)
  let duration=CMTimeGetSeconds(try await asset.load(.duration))
  let video=try await asset.loadTracks(withMediaType:.video),audio=try await asset.loadTracks(withMediaType:.audio)
  guard duration.isFinite,duration>0,duration<=600,!video.isEmpty,!audio.isEmpty else{throw ChartPackageError.invalid("Media must be a playable MP4 with video and audio, at most 10 minutes")}
  let chartData=try Data(contentsOf:CustomPackManifest.asset(package.chart,in:source));guard chartData.count<=8*1024*1024 else{throw ChartPackageError.invalid("Chart too large")}
  var chart:Chart
  if package.authoring==true{let authored=try JSONDecoder().decode(AuthoredChart.self,from:chartData);guard abs(authored.duration-duration)<0.15,authored.bpm==package.bpm else{throw ChartPackageError.invalid("Authoring metadata differs from media")};chart=try ChartAuthoringCompiler.compile(authored,declaredLanguage:package.inputLanguage)}else{chart=try JSONDecoder().decode(Chart.self,from:chartData)}
  if let declared=package.inputLanguage {
   let language=try NoteInputLanguage.parse(declared)
   guard chart.inputLanguage == nil || chart.inputLanguage == language else{throw ChartPackageError.invalid("Conflicting chart input language")}
   chart.inputLanguage=language
  }
  if chart.inputLanguage == nil {
   chart.inputLanguage=try InputLanguageResolver.resolve(declared:nil,targets:chart.events.compactMap{cue in let chars=Array(cue.parameter);return chars.count>=2 && chars.first=="0" ? String(chars[1]):nil})
  }
  try ChartDataValidator.validate(chart,duration:duration)
  let folderName="Custom_"+package.id
  let staged=fm.temporaryDirectory.appendingPathComponent("NegiCustom-"+UUID().uuidString,isDirectory:true)
  try fm.createDirectory(at:staged,withIntermediateDirectories:true);defer{try? fm.removeItem(at:staged)}
  report("copyingPack",0,0)
  try fm.copyItem(at:media,to:staged.appendingPathComponent("media.mp4"))
  try JSONEncoder().encode(chart).write(to:staged.appendingPathComponent("chart.json"))
  var cover:String?,titleArtwork:String?
  for (path,filename) in [(package.cover,"cover.png"),(package.titleArtwork,"title.png")] {
   if let path{let u=try CustomPackManifest.asset(path,in:source);let bytes=try Data(contentsOf:u);guard bytes.count<=16*1024*1024,let image=UIImage(data:bytes),let png=image.pngData() else{throw ChartPackageError.invalid("Invalid artwork")};try png.write(to:staged.appendingPathComponent(filename));if filename=="cover.png"{cover=folderName+"/"+filename}else{titleArtwork=folderName+"/"+filename}}
  }
  let song=Song(id:"custom."+package.id,title:package.title,artist:package.artist,art:"neutral-cover",eventCount:chart.events.count,folder:folderName,movie:folderName+"/media.mp4",chartPath:folderName+"/chart.json",artworkPath:cover,titleArtworkPath:titleArtwork,customMetadata:Song.Metadata(bpm:package.bpm,levels:package.levels,atlas:nil,artworkIndex:nil,titleAsset:nil),inputLanguage:chart.inputLanguage)
  for path in package.translations ?? [] {
   let bytes=try Data(contentsOf:CustomPackManifest.asset(path,in:source));guard bytes.count<=5*1024*1024 else{throw SubtitleError.invalid};let document=try JSONDecoder().decode(SubtitleDocument.self,from:bytes);try document.validate(songIDs:[song.id,package.id]);for track in document.translations{try JSONEncoder().encode(track).write(to:staged.appendingPathComponent("\(track.songID).lyrics.\(track.languageCode!).json"))}
  }
  try JSONEncoder().encode([song]).write(to:staged.appendingPathComponent("miku64-songs.json"))
  try fm.createDirectory(at:installRoot,withIntermediateDirectories:true)
  let dest=installRoot.appendingPathComponent(folderName),backup=fm.temporaryDirectory.appendingPathComponent("NegiPrevious-"+UUID().uuidString)
  let exists=fm.fileExists(atPath:dest.path)
  if exists{try fm.moveItem(at:dest,to:backup)}
  do{try fm.moveItem(at:staged,to:dest);if exists{try? fm.removeItem(at:backup)}}catch{if exists{try? fm.moveItem(at:backup,to:dest)};throw error}
  report("registeringPack",1,1)
 }
}
