import Foundation
import Combine

struct PackDownload:Codable,Identifiable {
 let id:UUID
 let url:URL
 let name:String
 var status:String
 var received:Int64=0
 var expected:Int64=0
 var speed:Double=0
 var file:String?
 var error:String?
 var fraction:Double? {expected>0 ? max(0,min(1,Double(received)/Double(expected))):nil}
}
struct ReleasePack:Decodable,Identifiable {
 let name:String
 let browser_download_url:URL
 let size:Int64
 var id:String {browser_download_url.absoluteString}
}
enum PackLink {
 static func file(_ url:URL)->URL? {
  guard url.scheme?.lowercased()=="https",url.host != nil,["zip","rar"].contains(url.pathExtension.lowercased()) else{return nil}
  if url.host?.lowercased()=="github.com" {
   let parts=url.pathComponents.filter{$0 != "/"}
   if parts.count>=5,parts[2]=="blob" {
    var components=URLComponents(url:url,resolvingAgainstBaseURL:false)
    components?.host="raw.githubusercontent.com";components?.path="/"+([parts[0],parts[1]]+Array(parts.dropFirst(3))).joined(separator:"/")
    return components?.url
   }
  }
  return url
 }
 static func releaseAPI(_ url:URL)->URL? {
  guard url.scheme?.lowercased()=="https",url.host?.lowercased()=="github.com" else{return nil}
  let parts=url.pathComponents.filter{$0 != "/"}
  guard parts.count>=3,parts[2]=="releases" else{return nil}
  guard parts.count==3 || (parts.count==4 && parts[3]=="latest") || (parts.count>=5 && parts[3]=="tag") else{return nil}
  var components=URLComponents();components.scheme="https";components.host="api.github.com"
  if parts.count>=5,parts[3]=="tag"{
   let tag=parts.dropFirst(4).joined(separator:"/").addingPercentEncoding(withAllowedCharacters:.alphanumerics.union(CharacterSet(charactersIn:"-._~")))!
   components.path="/repos/"+parts[0]+"/"+parts[1]+"/releases/tags/"
   components.percentEncodedPath += tag
  }
  else{components.path="/repos/"+parts[0]+"/"+parts[1]+"/releases/latest"}
  return components.url
 }
}

@MainActor final class PackDownloads:NSObject,ObservableObject,URLSessionDownloadDelegate {
 static let shared=PackDownloads()
 @Published private(set) var items:[PackDownload]=[]
 @Published private(set) var available:[ReleasePack]=[]
 @Published private(set) var resolving=false
 @Published private(set) var linkError:String?
 private var tasks:[UUID:URLSessionDownloadTask]=[:]
 private var samples:[UUID:(Double,Int64)]=[:]
 private weak var importer:PackStore?
 private var importing=false
 nonisolated private static var downloads:URL {FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("Downloads",isDirectory:true)}
 nonisolated private static var stateRoot:URL {FileManager.default.urls(for:.libraryDirectory,in:.userDomainMask)[0].appendingPathComponent("PackDownloads",isDirectory:true)}
 private lazy var session:URLSession = {
  let config=URLSessionConfiguration.default
  config.httpMaximumConnectionsPerHost=4;config.timeoutIntervalForRequest=60
  return URLSession(configuration:config,delegate:self,delegateQueue:nil)
 }()
 private override init(){
  super.init()
  if let data=try? Data(contentsOf:Self.stateRoot.appendingPathComponent("tasks.json")),let saved=try? JSONDecoder().decode([PackDownload].self,from:data){
   items=saved.map{item in var copy=item;copy.speed=0;if ["downloading","importing"].contains(copy.status){copy.status=copy.file==nil ? "paused":"queued"};return copy}
  }
 }
 func bind(_ store:PackStore){importer=store;pumpImports()}
 func addLink(_ text:String) {
  linkError=nil;available=[]
  guard let url=URL(string:text.trimmingCharacters(in:.whitespacesAndNewlines)) else{linkError=Preferences.shared.text("httpsPackURL");return}
  if let direct=PackLink.file(url){add(direct);return}
  guard let api=PackLink.releaseAPI(url),!resolving else{linkError=Preferences.shared.text("httpsPackURL");return}
  resolving=true
  Task {
   defer{resolving=false}
   do {
    var request=URLRequest(url:api);request.setValue("application/vnd.github+json",forHTTPHeaderField:"Accept");request.setValue("MikuFlick64",forHTTPHeaderField:"User-Agent")
    let (data,response)=try await URLSession.shared.data(for:request)
    guard let http=response as? HTTPURLResponse,(200...299).contains(http.statusCode) else{throw URLError(.badServerResponse)}
    struct Release:Decodable {let assets:[ReleasePack]}
    let originalPacks=api.path.hasPrefix("/repos/HachiMiku39/mikuflick02_soundpack/")
    available=try JSONDecoder().decode(Release.self,from:data).assets.filter{asset in
     PackLink.file(asset.browser_download_url) != nil && (!originalPacks || asset.name.range(of:"^Mov_[0-9]+\\.(zip|rar)$",options:[.regularExpression,.caseInsensitive]) != nil)
    }
    if available.isEmpty{linkError=Preferences.shared.text("noPackDownloads")}
   }catch{linkError=localizedUIError(error)}
  }
 }
 func add(_ url:URL){
  guard let url=PackLink.file(url) else{linkError=Preferences.shared.text("httpsPackURL");return}
  if items.contains(where:{$0.url==url && ["downloading","paused","queued","importing"].contains($0.status)}){return}
  let item=PackDownload(id:UUID(),url:url,name:url.lastPathComponent,status:"downloading")
  items.insert(item,at:0);start(item.id)
 }
 private func start(_ id:UUID){
  guard let i=items.firstIndex(where:{$0.id==id}) else{return}
  let resumeURL=Self.stateRoot.appendingPathComponent(id.uuidString+".resume")
  let task:URLSessionDownloadTask
  if let resume=try? Data(contentsOf:resumeURL){task=session.downloadTask(withResumeData:resume);try? FileManager.default.removeItem(at:resumeURL)}
  else{items[i].received=0;items[i].expected=0;task=session.downloadTask(with:items[i].url)}
  items[i].status="downloading";items[i].error=nil;items[i].speed=0
  tasks[id]=task;samples[id]=(ProcessInfo.processInfo.systemUptime,items[i].received);task.taskDescription=id.uuidString;persist();task.resume()
 }
 func pause(_ id:UUID){
  guard let i=items.firstIndex(where:{$0.id==id}),items[i].status=="downloading",let task=tasks.removeValue(forKey:id) else{return}
  items[i].status="paused";items[i].speed=0;samples[id]=nil;persist()
  task.cancel{[weak self] data in guard let data else{return};Task{@MainActor [weak self] in
   guard let self,self.items.first(where:{$0.id==id})?.status=="paused" else{return}
   try? FileManager.default.createDirectory(at:Self.stateRoot,withIntermediateDirectories:true);try? data.write(to:Self.stateRoot.appendingPathComponent(id.uuidString+".resume"),options:.atomic)
  }}
 }
 func retry(_ id:UUID){
  guard let item=items.first(where:{$0.id==id}),["paused","failed","cancelled"].contains(item.status) else{return}
  if let file=item.file,FileManager.default.fileExists(atPath:Self.downloads.appendingPathComponent(file).path){
   if let i=items.firstIndex(where:{$0.id==id}){items[i].status="queued";items[i].error=nil;persist();pumpImports()}
  }else{start(id)}
 }
 func cancel(_ id:UUID){
  guard let i=items.firstIndex(where:{$0.id==id}),["downloading","paused","queued"].contains(items[i].status) else{return}
  items[i].status="cancelled";items[i].speed=0;tasks.removeValue(forKey:id)?.cancel();samples[id]=nil
  try? FileManager.default.removeItem(at:Self.stateRoot.appendingPathComponent(id.uuidString+".resume"));persist()
 }
 nonisolated func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didWriteData bytesWritten:Int64,totalBytesWritten:Int64,totalBytesExpectedToWrite:Int64){
  guard let text=downloadTask.taskDescription,let id=UUID(uuidString:text) else{return}
  let taskID=downloadTask.taskIdentifier
  Task{@MainActor [weak self] in
   guard let self,self.tasks[id]?.taskIdentifier==taskID,let i=self.items.firstIndex(where:{$0.id==id}),self.items[i].status=="downloading" else{return}
   let now=ProcessInfo.processInfo.systemUptime
   if let (time,bytes)=self.samples[id],now-time>=0.5{self.items[i].speed=max(0,Double(totalBytesWritten-bytes)/(now-time));self.samples[id]=(now,totalBytesWritten)}
   self.items[i].received=totalBytesWritten;self.items[i].expected=totalBytesExpectedToWrite
  }
 }
 nonisolated func urlSession(_ session:URLSession,downloadTask:URLSessionDownloadTask,didFinishDownloadingTo location:URL){
  guard let text=downloadTask.taskDescription,let id=UUID(uuidString:text) else{return}
  let taskID=downloadTask.taskIdentifier
  // The temporary URL is valid only during this delegate call.
  do {
   guard let http=downloadTask.response as? HTTPURLResponse,(200...299).contains(http.statusCode) else{throw URLError(.badServerResponse)}
   let name=id.uuidString+"-"+(downloadTask.originalRequest?.url?.lastPathComponent ?? "pack.zip")
   try FileManager.default.createDirectory(at:Self.downloads,withIntermediateDirectories:true)
   let saved=Self.downloads.appendingPathComponent(name)
   try FileManager.default.moveItem(at:location,to:saved)
   let size=(try saved.resourceValues(forKeys:[.fileSizeKey])).fileSize ?? 0
   Task{@MainActor [weak self] in
    guard let self,self.tasks[id]?.taskIdentifier==taskID,let i=self.items.firstIndex(where:{$0.id==id}),self.items[i].status=="downloading" else{return}
    self.items[i].file=name;self.items[i].received=Int64(size);self.items[i].expected=Int64(size);self.items[i].speed=0;self.items[i].status="queued";self.tasks[id]=nil;self.samples[id]=nil;self.persist();self.pumpImports()
   }
  }catch{let message=error.localizedDescription;Task{@MainActor [weak self] in guard let self,self.tasks[id]?.taskIdentifier==taskID else{return};self.fail(id,message:message)}}
 }
 nonisolated func urlSession(_ session:URLSession,task:URLSessionTask,didCompleteWithError error:Error?){
  guard let error,let text=task.taskDescription,let id=UUID(uuidString:text) else{return}
  let message=error.localizedDescription,taskID=task.taskIdentifier
  let data=(error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
  Task{@MainActor [weak self] in
   guard let self,self.tasks[id]?.taskIdentifier==taskID else{return}
   if let data{try? FileManager.default.createDirectory(at:Self.stateRoot,withIntermediateDirectories:true);try? data.write(to:Self.stateRoot.appendingPathComponent(id.uuidString+".resume"),options:.atomic)}
   self.fail(id,message:message)
  }
 }
 private func fail(_ id:UUID,message:String){
  guard let i=items.firstIndex(where:{$0.id==id}),items[i].status=="downloading" else{return}
  items[i].status="failed";items[i].error=message;items[i].speed=0;tasks[id]=nil;samples[id]=nil;persist()
 }
 func remove(_ id:UUID){
  guard let item=items.first(where:{$0.id==id}),["installed","failed","cancelled"].contains(item.status) else{return}
  items.removeAll{$0.id==id};try? FileManager.default.removeItem(at:Self.stateRoot.appendingPathComponent(id.uuidString+".resume"));persist()
 }
 private func persist(){
  try? FileManager.default.createDirectory(at:Self.stateRoot,withIntermediateDirectories:true)
  if let data=try? JSONEncoder().encode(items){try? data.write(to:Self.stateRoot.appendingPathComponent("tasks.json"),options:.atomic)}
 }
 private func pumpImports(){
  guard !importing,let importer,items.contains(where:{$0.status=="queued"}) else{return}
  importing=true
  Task {
   defer{importing=false}
   while let item=items.reversed().first(where:{$0.status=="queued"}),let file=item.file{
    while importer.installing{try? await Task.sleep(for:.seconds(0.5))}
    // Stable identity survives additions at the head of the list while waiting.
    guard let i=items.firstIndex(where:{$0.id==item.id}),items[i].status=="queued" else{continue}
    let id=item.id;items[i].status="importing";persist()
    importer.importArchive(Self.downloads.appendingPathComponent(file))
    while importer.installing{try? await Task.sleep(for:.seconds(0.5))}
    if let index=items.firstIndex(where:{$0.id==id}){items[index].status=importer.failed ? "failed":"installed";items[index].error=importer.failed ? importer.message:nil}
    persist()
   }
  }
 }
}
