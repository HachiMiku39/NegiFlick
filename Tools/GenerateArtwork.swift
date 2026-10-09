import AppKit
let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
func image(_ name:String,size:CGSize,icon:Bool=false)throws {
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:Int(size.width)*4,bitsPerPixel:32)!
 let context=NSGraphicsContext(bitmapImageRep:rep)!;NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current=context
 NSColor(calibratedRed:0.06,green:0.13,blue:0.16,alpha:1).setFill();NSBezierPath(rect:CGRect(origin:.zero,size:size)).fill()
 let edge=min(size.width,size.height),cell=edge*0.17,origin=CGPoint(x:size.width/2-cell*1.6,y:size.height/2-cell*1.3)
 for row in 0..<3{for col in 0..<3{let rect=CGRect(x:origin.x+CGFloat(col)*cell*1.1,y:origin.y+CGFloat(row)*cell*1.1,width:cell,height:cell);NSColor(calibratedRed:0.40,green:0.89,blue:0.69,alpha:row==col ? 1:0.22).setFill();NSBezierPath(roundedRect:rect,xRadius:cell*0.2,yRadius:cell*0.2).fill()}}
 if !icon {
  for (text,y,scale) in [("NegiFlick",size.height*0.82,0.09),("KANA SPRINT",size.height*0.15,0.04)]{
   let attrs:[NSAttributedString.Key:Any]=[.font:NSFont.systemFont(ofSize:edge*scale,weight:.semibold),.foregroundColor:NSColor.white];let dim=(text as NSString).size(withAttributes:attrs);(text as NSString).draw(at:CGPoint(x:(size.width-dim.width)/2,y:y),withAttributes:attrs)
  }
 }
 NSGraphicsContext.restoreGraphicsState()
 let output:NSBitmapImageRep
 if icon {
  // An RGB App Store icon has no alpha channel; copy the generated opaque pixels.
  let rgb=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(size.width),pixelsHigh:Int(size.height),bitsPerSample:8,samplesPerPixel:3,hasAlpha:false,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:Int(size.width)*3,bitsPerPixel:24)!
  for y in 0..<Int(size.height){for x in 0..<Int(size.width){rgb.setColor(rep.colorAt(x:x,y:y)!,atX:x,y:y)}}
  output=rgb
 }else{output=rep}
 try output.representation(using:.png,properties:[:])!.write(to:root.appendingPathComponent(name))
}
try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
try image("cover.png",size:CGSize(width:1024,height:1024))
try image("demo.png",size:CGSize(width:480,height:720))
try image("AppIcon.png",size:CGSize(width:1024,height:1024),icon:true)
