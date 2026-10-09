import Foundation
@MainActor final class Preferences {static let shared=Preferences();func text(_ key:String)->String{key}}
@MainActor final class PackStore {var installing=false;var failed=false;var message:String?;func importArchive(_ url:URL){}}
func localizedUIError(_ error:Error)->String{error.localizedDescription}
@main struct DownloadCheck {
 static func main()throws {
  func file(_ text:String)->String?{PackLink.file(URL(string:text)!)?.absoluteString}
  func release(_ text:String)->String?{PackLink.releaseAPI(URL(string:text)!)?.absoluteString}
  assert(file("http://example.com/Mov_1.zip")==nil)
  assert(file("file:///tmp/Mov_1.zip")==nil)
  assert(file("https://example.com/not-a-pack.exe")==nil)
  assert(file("https://example.com/Mov_98.RAR?token=public")=="https://example.com/Mov_98.RAR?token=public")
  assert(file("https://github.com/owner/repo/blob/main/folder/Mov_1.zip")=="https://raw.githubusercontent.com/owner/repo/main/folder/Mov_1.zip")
  assert(release("https://github.com/owner/repo/releases")=="https://api.github.com/repos/owner/repo/releases/latest")
  assert(release("https://github.com/owner/repo/releases/latest")=="https://api.github.com/repos/owner/repo/releases/latest")
  assert(release("https://github.com/owner/repo/releases/tag/v1.1.6-r4")=="https://api.github.com/repos/owner/repo/releases/tags/v1.1.6-r4")
  assert(release("https://github.com/owner/repo/releases/tag/test/version")=="https://api.github.com/repos/owner/repo/releases/tags/test%2Fversion")
  assert(release("https://github.com/owner/repo/releases/download/pack")==nil)
  assert(release("https://github.com/owner/repo/releases/tag")==nil)
  assert(release("https://notgithub.com/owner/repo/releases")==nil)
  assert(release("http://github.com/owner/repo/releases")==nil)
  print("PASS: HTTPS ZIP/RAR links, GitHub blob URLs and release tags; invalid protocols and page paths rejected")
  var item=PackDownload(id:UUID(),url:URL(string:"https://example.com/pack.zip")!,name:"pack.zip",status:"downloading")
  assert(item.fraction==nil)
  item.expected=100;item.received=25;assert(item.fraction==0.25)
  item.received=101;assert(item.fraction==1)
  item.received = -1;assert(item.fraction==0)
  item.expected = -1;assert(item.fraction==nil)
  item.status="paused";item.speed=512;item.file="downloaded.zip"
  let restored=try JSONDecoder().decode(PackDownload.self,from:JSONEncoder().encode(item))
  assert(restored.id==item.id && restored.status=="paused" && restored.file==item.file)
  print("PASS: unknown-length progress, bounded percentages and task history round trip")
 }
}
