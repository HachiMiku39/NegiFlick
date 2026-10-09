import Foundation
struct UTFTable {
 enum Value { case number(UInt64),text(String),bytes(Data) }
 static func rows(_ data:Data,base:Int)throws->(String,[[String:Value]]) {
  func integer(_ p:Int,_ n:Int)throws->UInt64 {guard p>=0,n>0,p+n<=data.count else{throw CocoaError(.fileReadCorruptFile)};return data[p..<p+n].reduce(0){($0<<8)|UInt64($1)}}
  let end=base+8+Int(try integer(base+4,4));guard end<=data.count,end>base+32 else{throw CocoaError(.fileReadCorruptFile)}
  let origin=base+8, rowBase=origin+Int(try integer(base+8,4)),strings=origin+Int(try integer(base+12,4)),blobs=origin+Int(try integer(base+16,4))
  let name=Int(try integer(base+20,4)),columns=Int(try integer(base+24,2)),width=Int(try integer(base+26,2)),count=Int(try integer(base+28,4))
  guard columns<=128,count<=100000,rowBase>=base,rowBase+width*count<=end else{throw CocoaError(.fileReadCorruptFile)}
  func string(_ index:Int)throws->String {let p=strings+index;guard p>=strings,p<end,let zero=data[p..<end].firstIndex(of:0),let s=String(data:data[p..<zero],encoding:.utf8) else{throw CocoaError(.fileReadCorruptFile)};return s}
  func read(_ p:Int,_ type:Int)throws->(Value,Int) {
   if type==10{return (.text(try string(Int(try integer(p,4)))),4)}
   if type==11 {let offset=Int(try integer(p,4)),length=Int(try integer(p+4,4));guard offset>=0,length>=0,blobs+offset+length<=end else{throw CocoaError(.fileReadCorruptFile)};return(.bytes(Data(data[blobs+offset..<blobs+offset+length])),8)}
   let size=[0:1,1:1,2:2,3:2,4:4,5:4,6:8,7:8,8:4][type];guard let size else{throw CocoaError(.fileReadCorruptFile)};return(.number(try integer(p,size)),size)
  }
  var cursor=base+32;var specs:[(String,Int,Int,Value?)]=[]
  for _ in 0..<columns {let flags=Int(try integer(cursor,1)),key=try string(Int(try integer(cursor+1,4)));cursor+=5;let storage=flags&0xf0,type=flags&15;var constant:Value?
   if storage==0x30 {let (v,n)=try read(cursor,type);constant=v;cursor+=n}
   guard [0x10,0x30,0x50].contains(storage) else{throw CocoaError(.fileReadCorruptFile)};specs.append((key,storage,type,constant))
  }
  var result:[[String:Value]]=[]
  for i in 0..<count {var p=rowBase+i*width;var row:[String:Value]=[:]
   for (key,storage,type,constant) in specs {if storage==0x50{let(v,n)=try read(p,type);row[key]=v;p+=n}else{row[key]=constant ?? .number(0)}};result.append(row)
  };return(try string(name),result)
 }
 static func chart(_ url:URL)throws->Chart {
  let file=try FileHandle(forReadingFrom:url);defer{try? file.close()};let data=try file.read(upToCount:1_048_576) ?? Data();var events:[[String:Value]]?;var unit=1000.0;var pos=0
  while let range=data.range(of:Data("@UTF".utf8),in:pos..<data.count) {pos=range.lowerBound+4
   if let(name,rows)=try? rows(data,base:range.lowerBound) {if name=="CUEPOINT_INFO"{events=rows};if name=="CUEPOINT_HDRINFO",case .number(let n)?=rows.first?["time_unit"]{unit=Double(n)}}
  }
  guard let events,unit>0 else{throw CocoaError(.fileReadCorruptFile)}
  func text(_ value:Value?)->String? {switch value{case .text(let s):return s;case .bytes(let d):return String(data:d.prefix{ $0 != 0 },encoding:.utf8);default:return nil}}
  let cues=events.compactMap { row->Cue? in guard text(row["name"])=="note",case .number(let t)?=row["time"],let p=text(row["parameter"]),!p.isEmpty else{return nil};return Cue(time:Double(t)/unit,parameter:p) }
  guard !cues.isEmpty else{throw CocoaError(.fileReadCorruptFile)};return Chart(events:cues.sorted{$0.time<$1.time})
 }
}
