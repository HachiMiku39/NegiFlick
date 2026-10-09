import SwiftUI
import CoreText
import AVFoundation
import UniformTypeIdentifiers
import WebKit
import Darwin

final class NegiApplicationDelegate:NSObject,UIApplicationDelegate {
 private static let modelIdentifier:String = {
  #if targetEnvironment(simulator)
  return ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] ?? ""
  #else
  var info=utsname();uname(&info);let capacity=MemoryLayout.size(ofValue:info.machine)
  return withUnsafePointer(to:&info.machine){pointer in
   pointer.withMemoryRebound(to:CChar.self,capacity:capacity){String(cString:$0)}
  }
  #endif
 }()
 func application(_ application:UIApplication,supportedInterfaceOrientationsFor window:UIWindow?)->UIInterfaceOrientationMask {
  let isPad=(window?.traitCollection.userInterfaceIdiom ?? UIDevice.current.userInterfaceIdiom) == .pad
  return DeviceOrientationPolicy.supportsLandscape(isPad:isPad,modelIdentifier:Self.modelIdentifier) ? (isPad ? .all:.allButUpsideDown):.portrait
 }
}

// Futura is the Latin face, with an explicit CJK cascade. A mixed label therefore uses
// Futura for English/digits and PingFang for Chinese without replacing bitmap artwork.
enum AppFont {
 static func uiFont(size:CGFloat,weight:UIFont.Weight = .regular)->UIFont {
  let language=Language.system()
  let chinese=weight.rawValue>=UIFont.Weight.semibold.rawValue ? "PingFangSC-Semibold":weight.rawValue>=UIFont.Weight.medium.rawValue ? "PingFangSC-Medium":"PingFangSC-Regular"
  let fallback=UIFont(name:language == .ja || language == .ko ? TypographyPolicy.fallback(language:language):chinese,size:size) ?? .systemFont(ofSize:size,weight:weight)
  guard let latin=UIFont(name:TypographyPolicy.latin,size:size) else{return fallback}
  let cascade=[fallback.fontDescriptor,UIFontDescriptor(name:chinese,size:size)]
  return UIFont(descriptor:latin.fontDescriptor.addingAttributes([.cascadeList:cascade]),size:size)
 }
 static func system(size:CGFloat,weight:UIFont.Weight = .regular,design:Font.Design = .default)->Font {Font(uiFont(size:size,weight:weight))}
 static func style(_ style:UIFont.TextStyle,weight:UIFont.Weight = .regular)->Font {
  let size=UIFont.preferredFont(forTextStyle:style,compatibleWith:UITraitCollection(preferredContentSizeCategory:.large)).pointSize
  return Font(UIFontMetrics(forTextStyle:style).scaledFont(for:uiFont(size:size,weight:weight)))
 }
 static var largeTitle:Font {style(.largeTitle)}
 static var title:Font {style(.title1)}
 static var title2:Font {style(.title2)}
 static var title3:Font {style(.title3)}
 static var headline:Font {style(.headline,weight:.semibold)}
 static var subheadline:Font {style(.subheadline)}
 static var body:Font {style(.body)}
 static var callout:Font {style(.callout)}
 static var caption:Font {style(.caption1)}
 static var caption2:Font {style(.caption2)}
 static var footnote:Font {style(.footnote)}
}

extension Color {
 init(hex: UInt32) { self.init(red:Double((hex>>16)&255)/255,green:Double((hex>>8)&255)/255,blue:Double(hex&255)/255) }
}
extension Difficulty {
 // DX-inspired palette. BTL is the exact colour requested by the user.
 var color:Color { Color(hex:[0x45C768,0xF6CC36,0xEF5365,0xAB74EC,0xCCCCFF][rawValue]) }
}
extension Judgement {
 var color:Color { Color(hex:[0xFFFFFF,0xAD7DEB,0x64CF80,0xCD9565,0xD7DFEB,0xF6D16B][rawValue]) }
}
struct StageBackground:View {
 var body:some View { ZStack {
  LinearGradient(colors:[Color(hex:0x103846),backdrop,Color(hex:0x171E38)],startPoint:.topLeading,endPoint:.bottomTrailing)
  GeometryReader { g in ForEach(0..<8) { i in RoundedRectangle(cornerRadius:7).stroke(teal.opacity(0.07),lineWidth:1).frame(width:90,height:90).rotationEffect(.degrees(45)).position(x:g.size.width*CGFloat((i*3)%9)/8,y:g.size.height*CGFloat(i)/7) } }
 }.ignoresSafeArea().allowsHitTesting(false) }
}
@main struct NegiFlickApp:App {
 @UIApplicationDelegateAdaptor(NegiApplicationDelegate.self) private var appDelegate
 init(){
  AppleMetalHUD.apply(enabled:Preferences.shared.effectiveMetalHUD)
  let appearance=UINavigationBarAppearance();appearance.configureWithDefaultBackground()
  appearance.titleTextAttributes=[.font:AppFont.uiFont(size:17,weight:.semibold)]
  appearance.largeTitleTextAttributes=[.font:AppFont.uiFont(size:34,weight:.semibold)]
  UINavigationBar.appearance().standardAppearance=appearance;UINavigationBar.appearance().scrollEdgeAppearance=appearance
 }
 var body:some Scene{WindowGroup{LaunchRootView().background(PerformanceOverlayAnchor()).font(AppFont.body).preferredColorScheme(.dark)}}
}
struct LaunchRootView:View {
 @State private var completed=false
 var body:some View {if completed{HomeView()}else{CopyrightLaunchView{completed=true}}}
}
struct CopyrightLaunchView:View {
 let completion:()->Void
 var body:some View {Button(action:completion){ZStack{StageBackground();VStack(spacing:12){Image(systemName:"keyboard").font(.system(size:70)).foregroundStyle(teal);Text("NegiFlick").font(.system(size:44,weight:.bold,design:.rounded));Text("INPUT RHYTHM").font(.system(.caption,design:.monospaced)).tracking(4)}}}.buttonStyle(.plain).task{try? await Task.sleep(for:.seconds(1));if !Task.isCancelled{completion()}}.accessibilityLabel("NegiFlick. Tap to continue")}
}
enum SelectionStyle:String,CaseIterable,Identifiable {
 case legacy="LEGACY",sekaiA="SEKAI-A",sekaiB="SEKAI-B"
 var id:String {rawValue}
 @MainActor var title:String {Preferences.shared.text(["legacyStyle","sekaiAStyle","sekaiBStyle"][Self.allCases.firstIndex(of:self)!])}
}
extension Difficulty {
 @MainActor var localizedLabel:String {Preferences.shared.text(["difficultyEasy","difficultyNormal","difficultyHard","difficultyExtreme","difficultyBreak"][rawValue])}
}
extension Judgement {
 @MainActor var localizedLabel:String {Preferences.shared.text(["judgementNone","judgementWorst","judgementSad","judgementSafe","judgementFine","judgementCool"][rawValue])}
}
extension KeyboardStyle {
 @MainActor var localizedLabel:String {Preferences.shared.text(["keyboardOriginal","keyboardRomanSupport","keyboardFullRoman"][rawValue])}
}
struct LegacyBackground:View {
 var name="neutral"
 var body:some View {StageBackground()}
}
// These two atlas headings are English artwork in every locale.
struct ArtworkScreenHeading:View {
 let title:String;var expanded=false;var color=Color(hex:0xA8EDCD)
 var body:some View {Text(title).font(.system(size:expanded ? 32:26,weight:.medium,design:.monospaced)).tracking(expanded ? 6:3).foregroundStyle(color).shadow(color:Color.cyan.opacity(0.25),radius:2).lineLimit(1).frame(maxWidth:.infinity).frame(height:40).accessibilityAddTraits(.isHeader)}
}
enum SceneLoading {static let minimumDuration:Duration = .seconds(1)}
struct ScreenTransition:ViewModifier {
 @State private var visible=true;@State private var started=false;var gameLoad=false;var waiting=false;var once=false;var onReady:(()->Void)?=nil
 func body(content:Content)->some View {content.overlay{if visible || waiting{Group{if gameLoad{GameLoadingScreen()}else{LoadingScreen()}}.zIndex(100)}}.task{guard !once || !started else{return};started=true;visible=true;defer{visible=false;if !Task.isCancelled{onReady?()}};try? await Task.sleep(for:SceneLoading.minimumDuration)}}
}
extension View {func screenTransition(game:Bool=false,waiting:Bool=false,once:Bool=false,onReady:(()->Void)?=nil)->some View{modifier(ScreenTransition(gameLoad:game,waiting:waiting,once:once,onReady:onReady))}}
struct LoadingScreen:View {
 var body:some View {ZStack{StageBackground();VStack(spacing:24){Image(systemName:"keyboard").font(.system(size:54)).foregroundStyle(teal);ProgressView();Text("Loading...").font(.system(.title3,design:.monospaced)).foregroundStyle(.white)}}.accessibilityLabel(Preferences.shared.text("loading"))}
}
struct GameLoadingScreen:View {var body:some View {LoadingScreen()}}
struct SoundButtonStyle:ButtonStyle {
 var prominent=false;@Environment(\.isEnabled) private var enabled
 func makeBody(configuration:Configuration)->some View {configuration.label.padding(prominent ? 10:0).background(prominent ? teal:Color.clear,in:RoundedRectangle(cornerRadius:12)).opacity(configuration.isPressed ? 0.75:1).onChange(of:configuration.isPressed){_,pressed in if pressed && enabled{SoundEffects.shared.play("SE02_01")}}}
}
enum LegacyUIFont {
 static func isEnglish(_ text:String)->Bool {text.unicodeScalars.allSatisfy{$0.value<128} && text.contains(where:{$0.isLetter})}
 static func title(_ text:String,size:CGFloat)->Font {AppFont.system(size:size,weight:.medium)}
}

struct LegacyButton:View {
 let title:String;var symbol:String?=nil;var height:CGFloat=56
 var body:some View {GeometryReader{g in
  let scale=min(g.size.width/394,g.size.height/82),w=394*scale,h=82*scale
  ZStack{OriginalSprite(name:"menubutton_l_base");HStack(spacing:10){if let symbol{Image(systemName:symbol).font(AppFont.system(size:h*0.34))};LegacyCenteredText(title:title,size:max(17,h*(LegacyUIFont.isEnglish(title) ? 0.39:0.34)))}.padding(.horizontal,h*0.22).padding(.vertical,h*0.18)}.frame(width:w,height:h).position(x:g.size.width/2,y:g.size.height/2)
 }.frame(height:height).contentShape(Rectangle()).foregroundStyle(.white).shadow(color:.black.opacity(0.3),radius:4,y:4).accessibilityElement(children:.ignore).accessibilityLabel(title)}
}
// CoreText supplies the glyph bounds, including baseline and asymmetric side bearings.
// The ink rectangle and the frame rectangle share a center; font metrics never move the label.
struct LegacyCenteredText:UIViewRepresentable {
 let title:String;let size:CGFloat
 func makeUIView(context:Context)->LegacyInkLabel {LegacyInkLabel()}
 func updateUIView(_ view:LegacyInkLabel,context:Context){view.title=title;view.pointSize=size;view.setNeedsDisplay()}
}
final class LegacyInkLabel:UIView {
 var title="";var pointSize:CGFloat=20
 override init(frame:CGRect){super.init(frame:frame);isOpaque=false;isUserInteractionEnabled=false;backgroundColor = .clear}
 required init?(coder:NSCoder){fatalError("init(coder:) has not been implemented")}
 override func draw(_ rect:CGRect){
  guard let context=UIGraphicsGetCurrentContext(),!title.isEmpty else{return}
  let font=AppFont.uiFont(size:pointSize,weight:.medium)
  let line=CTLineCreateWithAttributedString(NSAttributedString(string:title,attributes:[.font:font,.foregroundColor:UIColor.white]))
  let ink=CTLineGetBoundsWithOptions(line,[.useGlyphPathBounds,.excludeTypographicLeading])
  guard ink.width>0,ink.height>0 else{return}
  let scale=min(1,min(rect.width/ink.width,rect.height/ink.height))
  context.saveGState();context.translateBy(x:rect.midX,y:rect.midY);context.scaleBy(x:scale,y:-scale);context.textMatrix = .identity;context.textPosition=CGPoint(x:-ink.midX,y:-ink.midY);CTLineDraw(line,context);context.restoreGState()
 }
}
struct LegacyIconArtwork:View {
 let icon:String;let height:CGFloat
 var body:some View {GeometryReader{g in let scale=min(g.size.width/129,g.size.height/82),w=129*scale,h=82*scale;ZStack{OriginalSprite(name:"menubutton_s_base");OriginalSprite(name:icon).frame(height:h*0.48)}.frame(width:w,height:h).position(x:g.size.width/2,y:g.size.height/2)}.frame(height:height).contentShape(Rectangle())}
}
struct OriginalSprite:View {
 let name:String
 var body:some View {if let image=originalImage(name){Image(uiImage:image).resizable().scaledToFit()}}
}
struct OriginalRank:View {
 let rank:String
 var name:String {rank == "Perfect!" ? "perfect":String(format:"clearrank_%02d",["S","A","B","C","D","E"].firstIndex(of:rank) ?? 5)}
 var body:some View {OriginalSprite(name:name).accessibilityLabel(rank == "Perfect!" ? Preferences.shared.text("perfect"):rank)}
}
struct OriginalNumber:View {
 let value:Int;var height:CGFloat=20;var family="score"
 var body:some View {Text(String(max(0,value))).font(AppFont.system(size:height,weight:.bold,design:.rounded)).monospacedDigit().foregroundStyle(family == "combonumber" ? teal:.white).accessibilityLabel(String(value))}
}

struct ResultNumber:View {
 let value:Int;var height:CGFloat=22;var elapsed:Double = .infinity
 var body:some View {
  let columns=String(max(0,value)).count
  HStack(spacing:0){ForEach(0..<columns,id:\.self){index in
   Text(String(ResultCountup.digit(value:value,columnFromRight:columns-1-index,elapsed:elapsed)))
    .contentTransition(.numericText(countsDown:false))
    .animation(.easeOut(duration:0.055),value:elapsed)
  }}.font(AppFont.system(size:height,weight:.bold)).monospacedDigit().foregroundStyle(.white)
   .shadow(color:.black.opacity(0.8),radius:1,x:1,y:2).accessibilityElement(children:.ignore).accessibilityLabel(String(value))
 }
}
struct ResultEntrance<Content:View>:View {
 let duration:Double;@ViewBuilder let content:(Double)->Content
 @Environment(\.accessibilityReduceMotion) private var reduceMotion
 @State private var revealed=false;@State private var black=0.0
 @State private var elapsed=0.0;@State private var complete=false
 var body:some View {
  ZStack {
   if revealed {content(elapsed).disabled(!complete)}
   Color.black.opacity(black).ignoresSafeArea().allowsHitTesting(false)
   if !complete {Color.clear.contentShape(Rectangle()).ignoresSafeArea().onTapGesture{skip()}.accessibilityLabel("Skip result animation").accessibilityAddTraits(.isButton)}
  }.task {
   if reduceMotion {skip();return}
   do {
    withAnimation(.linear(duration:0.5)){black=1}
    try await Task.sleep(for:.milliseconds(500));guard !complete else{return}
    revealed=true
    withAnimation(.linear(duration:0.5)){black=0}
    try await Task.sleep(for:.milliseconds(500));guard !complete else{return}
    let start=ContinuousClock.now
    while elapsed<duration && !complete {
     try await Task.sleep(for:.milliseconds(40));guard !complete else{return}
     let time=start.duration(to:.now).components
     elapsed=min(duration,Double(time.seconds)+Double(time.attoseconds)/1e18)
    }
    guard !Task.isCancelled else{return};elapsed = .infinity;complete=true
   }catch{}
  }
 }
 func skip(){var transaction=Transaction();transaction.disablesAnimations=true;withTransaction(transaction){revealed=true;black=0;elapsed = .infinity;complete=true}}
}

struct HomeView:View {
 @StateObject private var packs=PackStore();@ObservedObject private var prefs=Preferences.shared
 @Environment(\.scenePhase) private var homePhase
 @State private var tutorial=false;@State private var importing=false;@State private var information=false
 @State private var titleReady=false
 @State private var homeVisible=false
 @AppStorage("tutorialSeen") private var seen=false
 var body:some View {NavigationStack{GeometryReader{g in
  homePresentation(g)
 }.ignoresSafeArea(.container,edges:UIDevice.current.userInterfaceIdiom == .pad ? .horizontal:[]).background(LegacyBackground(name:"bg_title")).toolbar(.hidden,for:.navigationBar).buttonStyle(SoundButtonStyle()).screenTransition(onReady:{titleReady=true;playTitleAnnouncement()})
 .sheet(isPresented:$importing,onDismiss:{playTitleAnnouncement()}){PackView(packs:packs).screenTransition().buttonStyle(SoundButtonStyle()).onAppear{MenuMusic.shared.play("BGM03")}}.sheet(isPresented:$information,onDismiss:{playTitleAnnouncement()}){InformationView().screenTransition().buttonStyle(SoundButtonStyle()).onAppear{MenuMusic.shared.play("BGM03")}}.sheet(isPresented:$tutorial,onDismiss:{playTitleAnnouncement()}){TutorialView{seen=true;tutorial=false}.screenTransition().buttonStyle(SoundButtonStyle()).onAppear{MenuMusic.shared.play("BGM03")}}
 .onAppear{homeVisible=true;PackDownloads.shared.bind(packs);playTitleAnnouncement()}.onDisappear{homeVisible=false}.onChange(of:homePhase){_,phase in if phase == .active{MenuMusic.shared.resume();playTitleAnnouncement()}else{MenuMusic.shared.suspend()}}
 .task{
 traceMenuAudio("HOME tutorialSeen=\(seen)");if !seen{tutorial=true}

}
 .onOpenURL{url in if ["zip","rar"].contains(url.pathExtension.lowercased()){importing=true;packs.importArchive(url)}}
 }}
 private func playTitleAnnouncement(){
  guard homeVisible,titleReady,homePhase == .active,!tutorial,!importing,!information else{return}
  MenuMusic.shared.playHomeAfterTitle()
 }
 @ViewBuilder func homePresentation(_ g:GeometryProxy)->some View {
  let wide=g.size.width>g.size.height
  VStack(spacing:wide ? 16:28){Spacer(minLength:12);Image(systemName:"keyboard").font(.system(size:wide ? 42:64)).foregroundStyle(teal);Text("NegiFlick").font(.system(size:wide ? 36:48,weight:.bold,design:.rounded));Text(prefs.language == .zh ? "输入法音游":"INPUT RHYTHM").font(.system(.subheadline,design:.monospaced)).tracking(3).foregroundStyle(.secondary)
   LazyVGrid(columns:wide ? [GridItem(.flexible()),GridItem(.flexible())]:[GridItem(.flexible())],spacing:14){homeMenuEntries(height:56)}.frame(maxWidth:wide ? 700:430)
   Spacer(minLength:12);HStack{NavigationLink{RecordsView()}label:{Label(prefs.text("result"),systemImage:"chart.bar")};Spacer();Button{information=true}label:{Label(prefs.text("information"),systemImage:"info.circle")}}.frame(maxWidth:430)
  }.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity)
 }
 @ViewBuilder func homeMenuEntries(height:CGFloat)->some View {NavigationLink{LibraryView(packs:packs,mv:false)}label:{LegacyButton(title:prefs.text("rhythmGame"),height:height)};NavigationLink{LibraryView(packs:packs,mv:true)}label:{LegacyButton(title:prefs.text("mvAction"),height:height)};NavigationLink{OptionsView()}label:{LegacyButton(title:prefs.text("optionsTitle"),height:height)};Button{importing=true}label:{LegacyButton(title:prefs.text("packInput"),height:height)}}
}
struct LibraryLaunch:Identifiable {
 let id=UUID()
 let song:Song;let songs:[Song];let difficulty:Difficulty
 let karaoke:Bool;let loop:Bool;let lyrics:Bool
}
struct LibraryView:View {
 @ObservedObject var packs:PackStore;let mv:Bool
 @ObservedObject private var prefs=Preferences.shared
 @AppStorage("selectionStyle") private var gameStyle=SelectionStyle.legacy.rawValue
 @AppStorage("mvStyle") private var mvStyle=SelectionStyle.legacy.rawValue
 @State private var chosenID="";@State private var launched:LibraryLaunch?;@State private var difficulty:Difficulty = .normal
 @State private var query="";@State private var descending=false;@State private var karaoke=false;@State private var ordinaryDifficulty:Difficulty = .normal
 @State private var playlistMode=false;@State private var playlistIDs:[String]=[];@State private var loop=false
 @AppStorage("mvShowLyrics") private var mvLyrics=true
 @State private var selectionSound=SoundEffects()
 @State private var carouselDrag:CGFloat=0
  @Environment(\.dismiss) private var dismiss
 var style:SelectionStyle {SelectionStyle(rawValue:mv ? mvStyle:gameStyle) ?? .legacy}
 var styleBinding:Binding<String> {mv ? $mvStyle:$gameStyle}
 var songs:[Song] {let list=packs.songs.filter{query.isEmpty || ($0.title+" "+$0.artist).localizedCaseInsensitiveContains(query)};return descending ? list.reversed():list}
 var chosen:Song? {packs.songs.first{$0.id==chosenID} ?? songs.first}
 var body:some View {GeometryReader{g in
  if style == .legacy {legacyPresentation(g)}
  else {VStack(spacing:12){
   Picker(prefs.text("style"),selection:styleBinding){ForEach(SelectionStyle.allCases){Text($0.title).tag($0.rawValue)}}.pickerStyle(.segmented)
   HStack{Image(systemName:"magnifyingglass");TextField(prefs.text("songSearch"),text:$query);if !query.isEmpty{Button{query=""}label:{Image(systemName:"xmark.circle.fill")}};Button{descending.toggle()}label:{Image(systemName:"arrow.up.arrow.down")}}.padding(12).background(.white.opacity(0.12),in:RoundedRectangle(cornerRadius:14))
   if g.size.width>g.size.height {HStack(alignment:.top,spacing:22){catalog.frame(maxWidth:.infinity);if let song=chosen{ScrollView{detail(song,compact:g.size.height<600,short:g.size.height<600)}.frame(width:min(390,g.size.width*0.42))}}}
   else {if let song=chosen{detail(song,compact:true)};catalog}
  }.padding(16).frame(maxWidth:1100).frame(maxWidth:.infinity,maxHeight:.infinity).background(SekaiBackground())}
 }.toolbar(.visible,for:.navigationBar).navigationTitle("").navigationBarTitleDisplayMode(.inline).navigationBarBackButtonHidden(true)
 .toolbar{
  ToolbarItem(placement:.topBarLeading){Button{dismiss()}label:{Image(systemName:"chevron.left").frame(width:44,height:44)}.accessibilityLabel(prefs.text("back"))}
  ToolbarItem(placement:.principal){Text("MUSIC SELECT").font(.system(size:22,weight:.medium,design:.monospaced)).tracking(2).foregroundStyle(style == .legacy ? Color(hex:0xA8EDCD):Color(hex:0xE1FAFF)).shadow(color:Color.cyan.opacity(0.25),radius:2).lineLimit(1).minimumScaleFactor(0.8).accessibilityAddTraits(.isHeader)}
  if style != .legacy {ToolbarItem(placement:.topBarTrailing){Text("\(packs.songs.count)").font(AppFont.caption).foregroundStyle(.white)}}
 }.buttonStyle(SoundButtonStyle()).screenTransition()
 .onAppear{if chosenID.isEmpty{chosenID=packs.songs.first?.id ?? ""};if let song=chosen{SongPreview.shared.play(song)}}
 .onChange(of:chosenID){old,new in if !old.isEmpty && !new.isEmpty && old != new {selectionSound.play("SE03")};if mv && playlistMode && old != new && !new.isEmpty && !playlistIDs.contains(new){playlistIDs.append(new)};if let song=chosen{SongPreview.shared.play(song)}}
 .fullScreenCover(item:$launched,onDismiss:{if let song=chosen{SongPreview.shared.play(song)}}){launch in if mv {MVSessionView(songs:launch.songs,karaoke:launch.karaoke,loop:launch.loop,lyrics:launch.lyrics)}else{GameView(song:launch.song,difficulty:launch.difficulty,mode:.play)}} }
 @ViewBuilder func legacyPresentation(_ g:GeometryProxy)->some View {
  let w=g.size.width,h=g.size.height,wide=w>h
  let spacious=w>=700 && h>=650
  let footerHeight:CGFloat=56,dockHeight:CGFloat=84
  let footerWidth=max(0,min(w-40,360))
  // Account for the navigation/status region so the cover itself meets the screen center.
  let sceneTop=max(0,g.frame(in:.global).minY)
  let screenCenterY=(h-sceneTop+g.safeAreaInsets.bottom)/2
  let proposedCover=min(w*(wide ? 0.27:0.54),h*(wide ? 0.44:0.32))
  let compactHeader = !wide && h<650
  let phoneTitleScale:CGFloat = UIDevice.current.userInterfaceIdiom == .phone && !wide && w<600 ? 1.45:1
  let titleHeight:CGFloat=wide ? min(92,max(28,proposedCover*0.34),max(28,screenCenterY-proposedCover/2-16)) : min((spacious ? 150:(compactHeader ? 56:105))*phoneTitleScale,max(compactHeader ? 36:64,proposedCover*(compactHeader ? 0.32:0.40))*phoneTitleScale)
  let detailsBottom=h-dockHeight-16
  // Fit the complete vertical group before placing its center. Preserve readable controls
  // and allow the cover to move only when the available height requires it.
  let cover=wide ? proposedCover:min(proposedCover,max(64,(detailsBottom-18-titleHeight-22-158-8)/1.18))
  let centerY=wide ? screenCenterY:min(max(screenCenterY,18+titleHeight+22+cover/2),detailsBottom-cover*0.68-158-8)
  let carouselHeight=cover*1.18+6
  let detailsTop=centerY+cover*0.68+8
  VStack(spacing:0){ZStack {
   if wide {
    legacyTitle(height:titleHeight).frame(width:w*0.48).position(x:w*0.28,y:centerY-cover/2-12-titleHeight/2)
    legacyCarousel(height:carouselHeight,coverSize:cover).frame(width:w*0.54).position(x:w*0.28,y:centerY+cover*0.09+3)
    if let song=chosen{ScrollView{legacyDetails(song,compact:true,modeWidth:w*0.36,twoColumns:w*0.40<360).padding(.vertical,6).frame(minHeight:max(80,detailsBottom))}.scrollIndicators(.hidden).frame(width:w*0.40,height:max(80,detailsBottom)).position(x:w*0.76,y:detailsBottom/2)}
   }else{
    legacyTitle(height:titleHeight).frame(width:w*0.88).position(x:w/2,y:max(titleHeight/2+18,centerY-cover/2-titleHeight/2-22))
    legacyCarousel(height:carouselHeight,coverSize:cover).position(x:w/2,y:centerY+cover*0.09+3)
    if let song=chosen {
     legacyDetails(song,compact:true,modeWidth:min(404,w*0.80),compactHeader:compactHeader)
      .frame(width:w*0.94).position(x:w/2,y:(detailsTop+detailsBottom)/2)
    }
   }
  }.frame(width:w,height:max(1,h-dockHeight))
   Group{if chosen != nil{Button{launchSelection()}label:{LegacyButton(title:prefs.text("play"),height:footerHeight).frame(width:footerWidth).opacity(canLaunch ? 1:0.45)}.disabled(!canLaunch).accessibilityLabel(prefs.text(mv ? "playMV":"play"))}}.frame(maxWidth:.infinity).frame(height:dockHeight)
  }.frame(width:w,height:h).background(LegacyBackground(name:"bg_misicselect-adaptive"))
 }
 func legacyTitle(height:CGFloat)->some View {Group{if let song=chosen {if let title=song.titleImage {Image(uiImage:title).resizable().scaledToFit().accessibilityLabel(song.title)}else{VStack(spacing:6){Text(song.title).font(AppFont.system(size:max(17,height*0.30),weight:.bold,design:.serif)).multilineTextAlignment(.center);Text(song.artist).font(AppFont.system(size:max(13,height*0.13)))}}}}.foregroundStyle(.white).frame(height:height).frame(maxWidth:.infinity)}
 func legacyStars(_ song:Song,size:CGFloat)->some View {let stars=Int(song.level(difficulty)) ?? 0;return HStack(spacing:3){if stars>0 {ForEach(0..<stars,id:\.self){_ in OriginalSprite(name:difficulty == .breakLimit ? "difficultystar_01":"difficultystar_00").frame(width:size,height:size)}}else{Text("—")}}.accessibilityLabel(String(format:prefs.text("stars"),stars))}
 @ViewBuilder func legacyMetadataLabels(_ song:Song)->some View {if !mv{Text(prefs.text("highScore")+": \(UserDefaults.standard.integer(forKey:"originalRules.v1.best.\(song.id).\(difficulty.rawValue)"))")};if let bpm=song.metadata?.bpm{Text(prefs.text("bpm")+": \(bpm)")}}
 func legacyMetadata(_ song:Song,size:CGFloat,stacked:Bool=false)->some View {Group{if stacked{VStack(spacing:4){legacyMetadataLabels(song)}}else{HStack(spacing:12){legacyMetadataLabels(song)}}}.font(AppFont.system(size:max(17,size),weight:.medium)).lineLimit(1).minimumScaleFactor(0.8).foregroundStyle(.white).shadow(color:.black,radius:2)}
 func legacyDetails(_ song:Song,compact:Bool,scale:CGFloat=1,modeWidth:CGFloat=360,compactHeader:Bool=false,twoColumns:Bool=false)->some View {VStack(spacing:(compact ? 8:16)*scale){
  if twoColumns && !mv {legacyStars(song,size:18);legacyMetadata(song,size:17,stacked:true)}
  else if compactHeader && !mv {legacyStars(song,size:18);legacyMetadata(song,size:17)}
  else {if !mv{legacyStars(song,size:(compact ? 18:25)*scale)};legacyMetadata(song,size:(compact ? 12:16)*scale)}
  if mv {mvOptions(height:(compact ? 48:70)*scale)}
  else {
   Button{if difficulty == .breakLimit{difficulty=ordinaryDifficulty}else{ordinaryDifficulty=difficulty;difficulty = .breakLimit}}label:{OriginalSprite(name:difficulty == .breakLimit ? "modechange_on":"modechange_off").frame(maxWidth:modeWidth).frame(height:(compact ? 44:62)*scale)}.accessibilityLabel(prefs.text("modeChange")).accessibilityValue(prefs.text(difficulty == .breakLimit ? "difficultyBreak":"normalMode"))
   if difficulty == .breakLimit {legacyDifficultyRow([.breakLimit],height:56*scale).frame(maxWidth:270*scale)}
   else if twoColumns {VStack(spacing:8){legacyDifficultyRow(Array(Difficulty.allCases.prefix(2)),height:44);legacyDifficultyRow(Array(Difficulty.allCases.dropFirst(2).prefix(2)),height:44)}}
   else {legacyDifficultyRow(Array(Difficulty.allCases.prefix(4)),height:50*scale)}
  }
 }.frame(maxWidth:.infinity)}
 func legacyDifficultyRow(_ difficulties:[Difficulty],height:CGFloat)->some View {HStack(spacing:0){ForEach(difficulties){d in legacyDifficulty(d,height:height)}}.overlay{Rectangle().fill(Color(hex:0x9EEBF3).opacity(0.45)).frame(height:1).offset(y:6).allowsHitTesting(false).accessibilityHidden(true)}}
 func legacyDifficulty(_ d:Difficulty,height:CGFloat)->some View {Button{difficulty=d;if d != .breakLimit{ordinaryDifficulty=d}}label:{LegacyDifficultyArtwork(difficulty:d,selected:d==difficulty,rank:chosen.flatMap{GameRecord.bestRank(songID:$0.id,difficulty:d)}).frame(height:height).frame(maxWidth:.infinity)}.accessibilityLabel(d.localizedLabel).accessibilityValue(d==difficulty ? prefs.text("selected"):"")}
 func legacyCarousel(height:CGFloat,coverSize:CGFloat)->some View {GeometryReader{g in
  let cover=max(1,min(g.size.width*0.54,coverSize))
  let selected=packs.songs.firstIndex{$0.id==chosen?.id} ?? 0
  ZStack{ForEach(Array(packs.songs.enumerated()).filter{abs($0.offset-selected)<=5},id:\.element.id){index,song in
   let distance=CGFloat(index-selected)+carouselDrag/(cover*0.60)
   CoverFlowCard(image:song.image,cover:cover,height:height,distance:distance).overlay(alignment:.bottom){if mv && playlistMode && index==selected{OriginalSprite(name:playlistIDs.contains(song.id) ? "play_on":"play_off").frame(width:cover*0.18,height:cover*0.18).padding(.bottom,height*0.02)}}.zIndex(Double(10-abs(distance))).allowsHitTesting(false)
  }}.frame(width:g.size.width,height:height).clipped().contentShape(Rectangle())
  // Hit testing uses the visible side strips, rather than the overlapping unrotated card frames.
  .onTapGesture{location in
   let distance=location.x-g.size.width/2
   let steps=abs(distance)<=cover*0.5 ? 0:abs(distance)<=cover*0.71 ? 1:2+Int((abs(distance)-cover*0.71)/(cover*0.12))
   let index=min(packs.songs.count-1,max(0,selected+(distance<0 ? -steps:steps)))
   if packs.songs.indices.contains(index){choose(packs.songs[index])}
  }
  .gesture(DragGesture(minimumDistance:15).onChanged{value in carouselDrag=value.translation.width}.onEnded{value in
   let movement=value.predictedEndTranslation.width/(cover*0.60)
   let steps=Int(movement.rounded())
   let index=min(packs.songs.count-1,max(0,selected-steps))
   withAnimation(.spring(response:0.35,dampingFraction:0.86)){carouselDrag=0;if packs.songs.indices.contains(index){chosenID=packs.songs[index].id}}
  })
  .accessibilityElement(children:.ignore).accessibilityLabel(chosen?.title ?? prefs.text("coverFlow"))
  .accessibilityValue(mv && playlistMode && playlistIDs.contains(chosenID) ? prefs.text("selected"):"")
  .accessibilityAdjustableAction{direction in let index=min(packs.songs.count-1,max(0,selected+(direction == .increment ? 1:-1)));if packs.songs.indices.contains(index){choose(packs.songs[index])}}
 }.frame(height:height) }
 func step(_ offset:Int){guard !packs.songs.isEmpty else{return};let i=packs.songs.firstIndex{$0.id==chosen?.id} ?? 0;withAnimation{chosenID=packs.songs[(i+offset+packs.songs.count)%packs.songs.count].id}}
 var canLaunch:Bool {chosen != nil && (!mv || !playlistMode || !playlistIDs.isEmpty)}
 func choose(_ song:Song){if mv && playlistMode{if chosenID==song.id && playlistIDs.contains(song.id){playlistIDs.removeAll{$0==song.id}}else if !playlistIDs.contains(song.id){playlistIDs.append(song.id)}};withAnimation(.spring(response:0.4)){chosenID=song.id}}
 func launchSelection(){
  guard canLaunch,let song=chosen else{return}
  let selected=mv && playlistMode ? playlistIDs.compactMap{id in packs.songs.first{$0.id==id}}:[song]
  guard !selected.isEmpty else{return}
  // The presented item owns the playlist; separate @State can be stale when the cover is created.
  let launch=LibraryLaunch(song:song,songs:selected,difficulty:difficulty,karaoke:karaoke,loop:mv && playlistMode && loop,lyrics:mvLyrics)
  SongPreview.shared.stop();launched=launch
 }
 func togglePlaylist(){playlistMode.toggle();if playlistMode{playlistIDs=chosen.map{[$0.id]} ?? []}else{loop=false}}
 func mvOptions(height:CGFloat)->some View {VStack(spacing:8){if playlistMode{Text(String(format:prefs.text("songsSelected"),playlistIDs.count,(packs.songs.firstIndex{$0.id==chosenID} ?? 0)+1,packs.songs.count)).font(AppFont.system(size:17,weight:.medium)).lineLimit(2)};HStack(spacing:12){mvOption("playlist",on:playlistMode,height:height){togglePlaylist()};mvOption("loop",on:loop,height:height){loop.toggle()}.disabled(!playlistMode).opacity(playlistMode ? 1:0.45);mvOption("lyrics",on:mvLyrics,height:height){mvLyrics.toggle()};mvOption("karaoke",on:karaoke,height:height){karaoke.toggle()}}}}
 func mvOption(_ name:String,on:Bool,height:CGFloat,action:@escaping()->Void)->some View {Button(action:action){OriginalSprite(name:name+(on ? "_on":"_off")).frame(maxWidth:.infinity).frame(height:height)}.accessibilityLabel(prefs.text(name)).accessibilityValue(prefs.text(on ? "on":"off"))}
 @ViewBuilder var catalog:some View {ScrollView{
  if songs.isEmpty {Text(prefs.text("noSongs")).padding(32)}
  else if style == .sekaiA {LazyVGrid(columns:[GridItem(.adaptive(minimum:95,maximum:180))],spacing:14){ForEach(songs){song in Button{chosenID=song.id}label:{VStack(alignment:.leading,spacing:5){artwork(song).aspectRatio(1,contentMode:.fit).overlay(alignment:.topLeading){if !mv{levelBadge(song)}};Text(song.title).font(AppFont.caption).lineLimit(2).frame(height:32,alignment:.topLeading)}.padding(6).background(chosen?.id==song.id ? .white.opacity(0.22):.clear,in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(chosen?.id==song.id ? teal:.clear,lineWidth:3))}.accessibilityLabel(song.title)}}}
  else {LazyVStack(spacing:8){ForEach(songs){song in Button{chosenID=song.id}label:{HStack(spacing:12){if !mv{levelBadge(song)};artwork(song).frame(width:58,height:58);VStack(alignment:.leading,spacing:5){Text(song.title).font(AppFont.headline).lineLimit(1);Text(song.artist).font(AppFont.caption).foregroundStyle(.white.opacity(0.65)).lineLimit(1)};Spacer();if chosen?.id==song.id{Image(systemName:"checkmark.circle.fill").foregroundStyle(teal)}}.padding(12).background(.white.opacity(chosen?.id==song.id ? 0.22:0.04),in:RoundedRectangle(cornerRadius:13))}.accessibilityLabel(song.title)}}}
 }.frame(maxHeight:.infinity)}
 func artwork(_ song:Song)->some View {Group{if let image=song.image{Image(uiImage:image).resizable().scaledToFit()}else{Image(systemName:"music.note").resizable().scaledToFit().padding(26).background(teal.opacity(0.2))}}.clipShape(RoundedRectangle(cornerRadius:style == .legacy ? 0:6))}
 func levelBadge(_ song:Song)->some View {Text(song.level(difficulty)).font(AppFont.title3).foregroundStyle(Color(hex:0x292740)).frame(width:42,height:42).background(difficulty.color,in:RoundedRectangle(cornerRadius:style == .sekaiA ? 6:21)).accessibilityLabel(prefs.text("level")+" "+song.level(difficulty))}
 func detail(_ song:Song,compact:Bool,short:Bool=false)->some View {VStack(spacing:short ? 6:12){
  if style != .legacy {if compact{HStack(spacing:14){artwork(song).frame(width:short ? 44:72,height:short ? 44:72);VStack(alignment:.leading,spacing:5){Text(song.title).font(AppFont.headline).lineLimit(2);Text(song.artist).font(AppFont.caption).foregroundStyle(.secondary);metadataLine(song)};Spacer()}}else{artwork(song).frame(maxHeight:260);Text(song.title).font(AppFont.title2);Text(song.artist).font(AppFont.caption);metadataLine(song)}}
  else {metadataLine(song)}
  if mv {mvOptions(height:short ? 42:60)}
  else {difficultyChoices(song,short:short)}
  Button{launchSelection()}label:{if style == .legacy{LegacyButton(title:prefs.text(mv ? "playMV":"play"),height:short ? 42:54)}else{Text(prefs.text(mv ? "playMV":"play")).font(AppFont.headline).tracking(2).frame(maxWidth:.infinity).padding(short ? 8:14).background(teal,in:Capsule()).foregroundStyle(Color(hex:0x243D50))}}.disabled(!canLaunch).accessibilityLabel(prefs.text(mv ? "playMV":"play"))
 }.padding(style == .legacy ? 0:short ? 10:14).background {if style != .legacy {RoundedRectangle(cornerRadius:24).fill(Color(hex:0x45415F).opacity(0.9)).overlay(RoundedRectangle(cornerRadius:24).stroke(.white.opacity(0.23),lineWidth:2))}} }
 func metadataLine(_ song:Song)->some View {HStack{if let bpm=song.metadata?.bpm{Text(prefs.text("bpm")+" \(bpm)")};Spacer();if !mv{Text(prefs.text("highScore")+" \(UserDefaults.standard.integer(forKey:"originalRules.v1.best.\(song.id).\(difficulty.rawValue)"))")}}.font(AppFont.caption).foregroundStyle(.white.opacity(0.7))}
 func difficultyChoices(_ song:Song,short:Bool=false)->some View {VStack(spacing:short ? 6:8){LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8){ForEach(Array(Difficulty.allCases.prefix(4))){d in difficultyButton(d,song,short:short)}};difficultyButton(.breakLimit,song,short:short)}}
 func difficultyButton(_ d:Difficulty,_ song:Song,short:Bool=false)->some View {Button{difficulty=d}label:{HStack(spacing:8){Text(prefs.text("level")+" "+song.level(d)).font(AppFont.headline).lineLimit(1).minimumScaleFactor(0.6);Text(d.localizedLabel).font(AppFont.caption).lineLimit(1).minimumScaleFactor(0.5);Spacer(minLength:0);if d==difficulty{Image(systemName:"checkmark.circle.fill")}}.padding(.horizontal,10).frame(height:44).frame(maxWidth:.infinity).foregroundStyle(d.color).background(d.color.opacity(d==difficulty ? 0.24:0.07),in:RoundedRectangle(cornerRadius:12)).overlay(RoundedRectangle(cornerRadius:12).stroke(d.color.opacity(d==difficulty ? 1:0.25),lineWidth:d==difficulty ? 2:1))}.accessibilityLabel(d.localizedLabel+" "+prefs.text("level")+" "+song.level(d))}
}
struct LegacyDifficultyArtwork:View {
 let difficulty:Difficulty;let selected:Bool;var rank:String?=nil
 var body:some View {GeometryReader{g in
  let cursorWidth:CGFloat=difficulty == .breakLimit ? 271:164
  let scale=min(max(1,g.size.width-8)/cursorWidth,g.size.height/66)
  let textSize:CGFloat=17
  ZStack{if selected{RoundedRectangle(cornerRadius:7).fill(teal.opacity(0.18)).overlay(RoundedRectangle(cornerRadius:7).stroke(teal,lineWidth:1.5)).frame(width:cursorWidth*scale,height:30).offset(y:-6)};difficultyLabel(size:textSize,color:selected ? .white:Color(hex:0x6BE5EC)).offset(y:-6);difficultyLabel(size:textSize,color:Color(hex:0x6BE5EC)).scaleEffect(x:1,y:-1).frame(height:12,alignment:.top).clipped().mask(LinearGradient(colors:[Color.black.opacity(0.35),.clear],startPoint:.top,endPoint:.bottom)).offset(y:16).accessibilityHidden(true)}.frame(width:g.size.width,height:g.size.height).overlay(alignment:.topTrailing){if let rank{Group{if ["D","E"].contains(rank){Text(rank).font(AppFont.system(size:14,weight:.bold)).foregroundStyle(Color(hex:0xB6D2FF)).shadow(color:.black,radius:1)}else{OriginalSprite(name:rank == "Perfect!" ? "clearrank_star":"clearrank_"+rank.lowercased())}}.frame(width:18,height:18).padding(.trailing,4).offset(y:-7).accessibilityLabel(rank)}}
 }}
 func difficultyLabel(size:CGFloat,color:Color)->some View {Text(difficulty.localizedLabel).font(AppFont.system(size:size,weight:.medium)).lineLimit(1).minimumScaleFactor(0.75).foregroundStyle(color).padding(.horizontal,6)}
}
struct CoverFlowCard:View {
 let image:UIImage?;let cover:CGFloat;let height:CGFloat;let distance:CGFloat
 @ViewBuilder var picture:some View {if let image{Image(uiImage:image).resizable().scaledToFit()}else{Color.cyan.opacity(0.2)}}
 var body:some View {VStack(spacing:6){picture.frame(width:cover,height:cover);picture.frame(width:cover,height:cover).scaleEffect(x:1,y:-1).mask(LinearGradient(colors:[Color.black.opacity(0.35),Color.clear],startPoint:.top,endPoint:.bottom)).frame(height:cover*0.18,alignment:.top).clipped()}.frame(width:cover,height:height)
  .rotation3DEffect(.degrees(Double(max(-1,min(1,distance)))*(-75)),axis:(x:0,y:1,z:0),perspective:0.65)
  .scaleEffect(1-min(1,abs(distance))*0.06)
  .offset(x:cover*(distance<0 ? -1:1)*(min(1,abs(distance))*0.59+max(0,abs(distance)-1)*0.12))
 }
}
struct SekaiBackground:View {
 var body:some View {ZStack{LinearGradient(colors:[Color(hex:0x817E9D),Color(hex:0x38334F)],startPoint:.topLeading,endPoint:.bottomTrailing);GeometryReader{g in ForEach(0..<12){i in Rectangle().fill([Color.cyan,Color.pink,Color.orange][i%3].opacity(0.08)).frame(width:130,height:130).rotationEffect(.degrees(25)).position(x:g.size.width*CGFloat((i*7)%13)/12,y:g.size.height*CGFloat(i)/11)}}}.ignoresSafeArea().allowsHitTesting(false)}
}
struct SettingsHeading:View {
 let title:String;var subtitle:String?=nil;var compact=false
 var body:some View {VStack(spacing:5){Text(title).font(AppFont.system(size:compact ? 30:40,weight:.medium)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.7);if let subtitle{Text(subtitle).font(AppFont.system(size:compact ? 16:20)).multilineTextAlignment(.center)}}.foregroundStyle(.white).shadow(color:.black.opacity(0.7),radius:1,x:1,y:2).frame(maxWidth:.infinity)}
}
struct OptionsView:View {
 @ObservedObject private var prefs=Preferences.shared
 var body:some View {GeometryReader{g in
  let wide=g.size.width>g.size.height
  VStack(spacing:wide ? 12:24){ArtworkScreenHeading(title:"OPTIONS",expanded:g.size.width>800).padding(.top,4);Text(prefs.text("chooseOptions")).font(AppFont.system(size:20)).foregroundStyle(.white);Spacer(minLength:0)
   LazyVGrid(columns:wide ? [GridItem(.flexible()),GridItem(.flexible())]:[GridItem(.flexible())],spacing:wide ? 10:16){ForEach(OptionCategory.allCases.filter{$0 != .developer || prefs.developerEnabled}){c in NavigationLink{OptionDetailView(category:c)}label:{LegacyButton(title:prefs.text(c.key).uppercased(),height:wide ? 48:64)}}}.frame(maxWidth:wide ? 740:470)
   Spacer(minLength:20)
  }.padding(20).frame(maxWidth:.infinity,maxHeight:.infinity)
 }.background(LegacyBackground()).navigationTitle("").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar).buttonStyle(SoundButtonStyle()).screenTransition(once:true).onAppear{MenuMusic.shared.play("BGM03")}}
}
enum OptionCategory:String,CaseIterable,Identifiable {case display="DISPLAY",audio="AUDIO",arrangement="HANDINESS",keyboard="KEYBOARD",help="HELP",developer="DEVELOPER";var id:String{rawValue};var key:String{self == .arrangement ? "handiness":rawValue.lowercased()}}
struct OptionDetailView:View {
 let category:OptionCategory
 @ObservedObject private var prefs=Preferences.shared
 @AppStorage("selectionStyle") private var gameStyle=SelectionStyle.legacy.rawValue
 @AppStorage("mvStyle") private var mvStyle=SelectionStyle.legacy.rawValue
 @AppStorage("showLyrics") private var lyrics=true
 @AppStorage("fullRoman") private var fullRoman=false
 @State private var tutorial=false
 var body:some View {Group{if category == .arrangement {HandinessOptions()}else if category == .audio {LegacyAudioOptions()}else if category == .keyboard {LegacyKeyboardOptions()}else{standardOptions}}.background(LegacyBackground()).navigationTitle("").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar).buttonStyle(SoundButtonStyle()).tint(teal).sheet(isPresented:$tutorial){TutorialView{tutorial=false}} }
 var standardOptions:some View {Form{
  Section{SettingsHeading(title:prefs.text(category.key)).padding(.vertical,22)}.listRowBackground(Color.clear)
  switch category {
  case .display:
   Section(prefs.text("rhythmGame")){Picker(prefs.text("style"),selection:$gameStyle){ForEach(SelectionStyle.allCases){Text($0.title).tag($0.rawValue)}}}
   Section(prefs.text("mvAction")){Picker(prefs.text("style"),selection:$mvStyle){ForEach(SelectionStyle.allCases){Text($0.title).tag($0.rawValue)}}};Toggle(prefs.text("lyrics"),isOn:$lyrics);Toggle(prefs.text("originalJudgements"),isOn:$prefs.originalJudgements);Toggle(prefs.text("timingHints"),isOn:$prefs.timingHints).disabled(prefs.originalJudgements);Toggle(prefs.text("developer"),isOn:$prefs.developerEnabled)
   Text(prefs.text("systemLanguage")).font(AppFont.footnote).foregroundStyle(.secondary)
  case .developer:
   Section{Toggle("Autoplay",isOn:$prefs.autoplay);Text(prefs.text("autoplayNote")).font(AppFont.footnote).foregroundStyle(.secondary)}
   Section{Toggle(prefs.text("performanceHUD"),isOn:$prefs.performanceHUD);Text(prefs.text("performanceHUDNote")).font(AppFont.footnote).foregroundStyle(.secondary)}
   Section{Toggle("Apple Metal HUD",isOn:$prefs.metalHUD);Text(prefs.text("metalHUDNote")).font(AppFont.footnote).foregroundStyle(.secondary);Link(prefs.text("metalHUDHelp"),destination:URL(string:"https://developer.apple.com/documentation/xcode/monitoring-your-metal-apps-graphics-performance")!)}
  case .audio,.arrangement:EmptyView()
  case .keyboard:EmptyView()
  case .help:
   Button(prefs.text("tutorial")){tutorial=true}.font(AppFont.system(size:24));Section{Text(prefs.text("t1body"));Text(prefs.text("t2body"));Text(prefs.text("t3body"))};Section{Text(prefs.text("originalHelpNote")).font(AppFont.footnote);ForEach(OriginalHelpContent.shared.pages){page in NavigationLink(page.title(prefs.language)){OriginalHelpDetail(page:page)}};NavigationLink(prefs.text("originalLicenses")){ScrollView{VStack(alignment:.leading,spacing:20){Text(prefs.text("originalLicensesNote"));Text(OriginalHelpContent.shared.licenseOriginal).textSelection(.enabled)}.font(AppFont.body).padding(24)}.background(LegacyBackground()).navigationTitle(prefs.text("originalLicenses"))}}header:{Text(prefs.text("originalHelp")).font(AppFont.system(size:26))}
  }
 }.font(AppFont.system(size:UIDevice.current.userInterfaceIdiom == .pad ? 20:17)).scrollContentBackground(.hidden) }
}
struct OriginalHelpContent:Decodable {
 struct Page:Decodable,Identifiable {
  let id:Int;let titles:[String:String];let bodies:[String:String]
  func title(_ language:Language)->String{titles[language.rawValue] ?? titles["en"] ?? ""}
  func body(_ language:Language)->String{bodies[language.rawValue] ?? bodies["en"] ?? ""}
 }
 let pages:[Page];let licenseOriginal:String
 static let shared:OriginalHelpContent = {
  guard let url=resource("original-help","json"),let data=try? Data(contentsOf:url),let value=try? JSONDecoder().decode(Self.self,from:data) else{return .init(pages:[],licenseOriginal:"")}
  return value
 }()
}
struct OriginalHelpDetail:View {
 let page:OriginalHelpContent.Page
 @ObservedObject private var prefs=Preferences.shared
 var body:some View{ScrollView{VStack(alignment:.leading,spacing:24){SettingsHeading(title:page.title(prefs.language)).padding(.top,30);Text(prefs.text("originalHelpNote")).font(AppFont.system(size:UIDevice.current.userInterfaceIdiom == .pad ? 18:15)).foregroundStyle(.secondary);Text(page.body(prefs.language)).font(AppFont.system(size:UIDevice.current.userInterfaceIdiom == .pad ? 23:19)).lineSpacing(8).textSelection(.enabled)}.padding(24).frame(maxWidth:850,alignment:.leading).frame(maxWidth:.infinity)}.background(LegacyBackground()).navigationTitle("").navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar)}
}
struct LegacyKeyboardOptions:View {
 @ObservedObject private var prefs=Preferences.shared
 @AppStorage("fullRoman") private var fullRoman=false
 @AppStorage("panelGuide") private var panelGuide=true
 @AppStorage("flower") private var flower=true
 var selection:KeyboardStyle {KeyboardStyle.selected(roman:prefs.roman,full:fullRoman)}
 var body:some View {GeometryReader{g in
  let width=max(0,min(820,g.size.width-36)),wide=g.size.width>g.size.height
  let cardHeight=min(330,(width-20)/3*315/247,g.size.height*(wide ? 0.43:0.34))
  ScrollView{VStack(spacing:wide ? 14:22){
   SettingsHeading(title:prefs.text("keyboardTitle"),subtitle:prefs.text("keyboardSettings"),compact:wide).padding(.top,wide ? 8:g.size.height*0.09)
   HStack(alignment:.center,spacing:10){ForEach(KeyboardStyle.allCases){style in Button{prefs.roman=style != .original;fullRoman=style == .fullRoman}label:{OriginalSprite(name:"keyboard_\(style.family)_\(selection == style ? "on":"off")").frame(maxWidth:.infinity).frame(height:cardHeight).scaleEffect(selection == style ? 1:0.9)}.accessibilityLabel(style.localizedLabel).accessibilityValue(selection == style ? prefs.text("selected"):"")}}
   keyboardToggle(family:"panelguide",value:$panelGuide,hint:"panelGuideHint",height:min(100,width*0.16))
   keyboardToggle(family:"flowet",value:$flower,hint:"flowerHint",height:min(120,width*0.20))
  }.foregroundStyle(.white).shadow(color:.black.opacity(0.7),radius:1,x:1,y:1).frame(width:width).padding(.bottom,26).frame(maxWidth:.infinity)}
 }}
 func keyboardToggle(family:String,value:Binding<Bool>,hint:String,height:CGFloat)->some View {VStack(spacing:9){
  HStack(spacing:10){Text(prefs.text(family == "flowet" ? "flower":"panelGuide")).font(AppFont.system(size:min(28,height*0.27))).lineLimit(2).minimumScaleFactor(0.7).frame(maxWidth:.infinity,alignment:.center);ForEach([true,false],id:\.self){enabled in Button{value.wrappedValue=enabled}label:{OriginalSprite(name:"\(family)_\(enabled ? "on":"off")_\(value.wrappedValue==enabled ? "on":"off")").frame(width:height*170/145,height:height).contentShape(Rectangle())}.accessibilityLabel(prefs.text(family == "flowet" ? "flower":"panelGuide")+" "+prefs.text(enabled ? "on":"off")).accessibilityValue(value.wrappedValue==enabled ? prefs.text("selected"):"")}}.frame(height:height).overlay(alignment:.bottom){Rectangle().fill(.white.opacity(0.25)).frame(height:1).allowsHitTesting(false)}
  Text(prefs.text(hint)).font(AppFont.system(size:UIDevice.current.userInterfaceIdiom == .pad ? 17:14)).foregroundStyle(.white.opacity(0.8)).frame(maxWidth:.infinity,alignment:.leading)
 }}
}
struct HandinessOptions:View {
 @ObservedObject private var prefs=Preferences.shared
 @AppStorage("handiness") private var selection=Handiness.right.rawValue
 var body:some View {GeometryReader{g in
  let wide=g.size.width>g.size.height
  ScrollView{VStack(spacing:wide ? 16:26){
   SettingsHeading(title:prefs.text("handiness"),compact:wide).padding(.top,wide ? 8:g.size.height*0.10)
   HStack(spacing:14){ForEach(Handiness.allCases){hand in Button{selection=hand.rawValue}label:{OriginalSprite(name:"\(hand.isLeft ? "lefthand":"righthand")_\(selection==hand.rawValue ? "on":"off")").frame(maxWidth:.infinity).frame(height:min(wide ? 240:390,g.size.width*0.57))}.accessibilityLabel(prefs.text(hand.isLeft ? "leftHand":"rightHand")).accessibilityValue(selection==hand.rawValue ? prefs.text("selected"):"")}}
   VStack(alignment:.leading,spacing:16){Text(prefs.text("handinessNote")).font(AppFont.headline);Text(prefs.text("handinessPortrait"));Text(prefs.text("handinessDuo"));Text(prefs.text("handinessWide"))}.font(AppFont.system(size:UIDevice.current.userInterfaceIdiom == .pad ? 19:15)).lineSpacing(4).frame(maxWidth:.infinity,alignment:.leading)
  }.padding(24).frame(maxWidth:680).frame(maxWidth:.infinity)}
 }}
}
struct LegacyAudioOptions:View {
 @ObservedObject private var prefs=Preferences.shared
 var body:some View {GeometryReader{g in
  let wide=g.size.width>g.size.height,compact=g.size.height<(wide ? 430:850)
  ScrollView{VStack(spacing:wide ? 8:compact ? 14:24){
   SettingsHeading(title:prefs.text("audio"),compact:wide || compact).padding(.top,wide ? 6:compact ? 12:32)
   Group{
    if wide {
     HStack(spacing:compact ? 18:28){
      VStack(spacing:compact ? 12:22){OriginalSprite(name:"speaker").frame(width:compact ? 84:110,height:compact ? 84:110);failSoundControls(compact:compact)}.frame(width:compact ? 156:200)
      VStack(spacing:compact ? 12:18){volumeControls(compact:compact)}.frame(maxWidth:.infinity)
     }.padding(compact ? 14:20).frame(maxWidth:850)
    }else{
     VStack(spacing:compact ? 10:16){OriginalSprite(name:"speaker").frame(width:compact ? 96:155,height:compact ? 96:155);volumeControls(compact:compact);failSoundControls(compact:compact)}.padding(compact ? 16:24).frame(maxWidth:560)
    }
   }.background{Image(uiImage:originalImage("volumewindow") ?? UIImage()).resizable().opacity(0.8)}
  }.padding(.horizontal,wide ? 16:22).padding(.bottom,wide ? 12:28).frame(width:g.size.width)}
 }.ignoresSafeArea(.container,edges:UIDevice.current.userInterfaceIdiom == .pad ? .horizontal:[])}
 @ViewBuilder func volumeControls(compact:Bool)->some View {
  LegacyVolumeControl(title:prefs.text("musicVolume"),value:$prefs.music,compact:compact)
  LegacyVolumeControl(title:prefs.text("sfxVolume"),value:$prefs.sfx,compact:compact)
 }
 func failSoundControls(compact:Bool)->some View {VStack(spacing:8){
  Text(prefs.text("failSound")).font(AppFont.system(size:compact ? 19:25)).multilineTextAlignment(.center)
  HStack(spacing:6){ForEach([true,false],id:\.self){enabled in Button{prefs.failSound=enabled}label:{OriginalSprite(name:"failedsound_\(enabled ? "on":"off")_\(prefs.failSound==enabled ? "w":"b")").frame(maxWidth:.infinity).frame(height:44).contentShape(Rectangle())}.accessibilityLabel(prefs.text(enabled ? "on":"off")).accessibilityValue(prefs.failSound==enabled ? prefs.text("selected"):"")}}
 }}
}
struct LegacyVolumeControl:View {
 let title:String;@Binding var value:Double;var compact=false
 var body:some View {VStack(spacing:compact ? 4:6){Text(title).font(AppFont.system(size:compact ? 20:25)).multilineTextAlignment(.center)
  GeometryReader{g in
   let meterWidth=max(1,min(g.size.width,compact ? 420:538)),segmentWidth=max(1,(meterWidth-38)/20)
   HStack(spacing:2){ForEach(0..<20,id:\.self){i in OriginalSprite(name:Double(i)<value*20 ? "volumemeter_on":"volumemeter_off").frame(width:segmentWidth,height:segmentWidth*34/25)}}
    .frame(width:meterWidth,height:g.size.height).contentShape(Rectangle())
    .gesture(DragGesture(minimumDistance:0).onChanged{value=min(1,max(0,$0.location.x/meterWidth))}.onEnded{_ in SoundEffects.shared.play("SE02_01")})
    .position(x:g.size.width/2,y:g.size.height/2)
  }.frame(height:compact ? 26:34).accessibilityElement().accessibilityLabel(title).accessibilityValue("\(Int(value*100))%").accessibilityAdjustableAction{direction in value=min(1,max(0,value+(direction == .increment ? 0.05:-0.05)))}
  HStack{Button{value=max(0,value-0.05)}label:{Text("−").frame(width:44,height:44)};Spacer();Button{value=min(1,value+0.05)}label:{Text("+").frame(width:44,height:44)}}.overlay{Text("\(Int(value*100))%").monospacedDigit().allowsHitTesting(false)}.font(AppFont.system(size:17))
 }.frame(maxWidth:.infinity).foregroundStyle(.white)}
}
struct RecordsView:View {
 @ObservedObject private var prefs=Preferences.shared
 @State private var records=GameRecord.all
 var body:some View {ScrollView{VStack(spacing:18){if records.isEmpty {Image(systemName:"crown").font(AppFont.system(size:60)).foregroundStyle(teal).padding(.top,100);Text(prefs.text("noRecords")).multilineTextAlignment(.center)}
 ForEach(records){r in VStack(spacing:12){HStack{Text(r.title).font(AppFont.headline);Spacer();Text(r.tally.rank == "Perfect!" ? prefs.text("perfect"):r.tally.rank).font(AppFont.title).foregroundStyle(Judgement.cool.color)};HStack{Text(Difficulty(rawValue:r.difficulty)?.localizedLabel ?? "").foregroundStyle(Difficulty(rawValue:r.difficulty)?.color ?? teal);Spacer();Text(r.date,style:.date)}.font(AppFont.caption);Divider();recordRow(prefs.text("totalScore"),r.tally.total);recordRow(prefs.text("totalNotes"),r.tally.totalNotes);recordRow(prefs.text("maxCombo"),r.tally.maxCombo);ForEach(Judgement.allCases.filter{$0 != .none}.reversed(),id:\.rawValue){j in HStack{Text(j.localizedLabel).foregroundStyle(j.color);Spacer();Text("\(r.tally.counts[j.rawValue])").monospacedDigit()}};Divider();recordRow(prefs.text("stageScore"),r.tally.stage);recordRow(prefs.text("comboBonus"),r.tally.bonus);recordRow(prefs.text("miniSuccess"),r.tally.interludeSuccess)}.padding(22).background(.white.opacity(0.12),in:RoundedRectangle(cornerRadius:20))}
 }.padding(20).frame(maxWidth:650).frame(maxWidth:.infinity)}.background(LegacyBackground(name:"bg_results")).navigationTitle(prefs.text("result")).navigationBarTitleDisplayMode(.inline).toolbar(.visible,for:.navigationBar).buttonStyle(SoundButtonStyle()).screenTransition().onAppear{records=GameRecord.all;MenuMusic.shared.play("BGM03")} }
 func recordRow(_ label:String,_ value:Int)->some View {HStack{Text(label);Spacer();Text("\(value)").monospacedDigit()}}
}
struct InformationView:View {
 @Environment(\.dismiss) private var dismiss
 @State private var address="https://github.com/HachiMiku39"
 @StateObject private var browser=InformationBrowser()
 var body:some View {NavigationStack{VStack(spacing:0){HStack{Button{browser.web.goBack()}label:{Image(systemName:"chevron.left")};Button{browser.web.goForward()}label:{Image(systemName:"chevron.right")};TextField(Preferences.shared.text("address"),text:$address).textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL).onSubmit{browser.load(address)};Button{browser.load(address)}label:{Image(systemName:"arrow.clockwise")}}.padding(14);WebSurface(web:browser.web)}.navigationTitle(Preferences.shared.text("information")).navigationBarTitleDisplayMode(.inline).toolbar{Button(Preferences.shared.text("done")){dismiss()}}}.onAppear{if browser.web.url==nil{browser.load(address)}} }
}
@MainActor final class InformationBrowser:ObservableObject {
 let web=WKWebView()
 func load(_ address:String){let value=address.contains("://") ? address:"https://"+address;guard let url=URL(string:value),["https","http"].contains(url.scheme?.lowercased() ?? "") else{return};web.load(URLRequest(url:url))}
}
struct WebSurface:UIViewRepresentable {
 let web:WKWebView
 func makeUIView(context:Context)->WKWebView{web}
 func updateUIView(_ uiView:WKWebView,context:Context){}
}

struct TutorialView:View {
 let complete:()->Void;@ObservedObject private var prefs=Preferences.shared;@State private var page=0
 var body:some View{VStack(spacing:24){
  Text(prefs.text("welcome")).font(AppFont.title2).multilineTextAlignment(.center)
  Image(systemName:["hand.draw.fill","music.note","play.rectangle.fill"][page]).font(AppFont.system(size:70)).foregroundStyle(teal).padding(20)
  Text(prefs.text("t\(page+1)")).font(AppFont.title)
  Text(prefs.text("t\(page+1)body")).font(AppFont.body).multilineTextAlignment(.center)
  if page==0{VStack(spacing:6){Text("う / u");HStack(spacing:24){Text("い / i");Text("あ / a");Text("え / e")};Text("お / o")}.font(AppFont.title3).foregroundStyle(teal)}
  Spacer();HStack{ForEach(0..<3){i in Circle().fill(i==page ? teal:.gray.opacity(0.4)).frame(width:8,height:8)}}
  Button(prefs.text(page==2 ? "start":"nextPage")){if page<2{page+=1}else{complete()}}.buttonStyle(SoundButtonStyle(prominent:true)).tint(teal).controlSize(.large)
 }.padding(28).background(backdrop).interactiveDismissDisabled()}
}
struct PackView:View {
 @ObservedObject var packs:PackStore;@ObservedObject private var prefs=Preferences.shared;@Environment(\.dismiss) private var dismiss;@Environment(\.openURL) private var openURL;@State private var picker=false;@State private var subtitlePicker=false;@State private var folderPicker=false;@State private var downloadList=false;@State private var subtitleMessage:String?;@State private var subtitleFailed=false
 var body:some View{NavigationStack{ScrollView{VStack(alignment:.leading,spacing:24){
  Text(prefs.text("packHint")).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
  Text(prefs.language == .zh ? "导入自制谱包或兼容曲包；下载列表支持你提供的链接。":"Import custom charts or compatible song packs. Add your own links in Downloads.").font(AppFont.callout)
  Button(prefs.text("import")){picker=true}.buttonStyle(SoundButtonStyle(prominent:true)).tint(teal).disabled(packs.installing)
  Button(prefs.text("importFolder")){folderPicker=true}.buttonStyle(SoundButtonStyle(prominent:true)).tint(teal).disabled(packs.installing)
  Text(prefs.text("packAccessHint")).font(AppFont.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
  Button(prefs.text("downloads")){downloadList=true}.buttonStyle(SoundButtonStyle(prominent:true))
  if packs.installing{ProgressView();Text(packs.progress)}
  if let message=packs.message{Text(message).foregroundStyle(packs.failed ? .red:teal).font(AppFont.callout).textSelection(.enabled)}
  NavigationLink(prefs.text("packFormat")){if let page=OriginalHelpContent.shared.pages.first(where:{$0.id==8}){OriginalHelpDetail(page:page)}}
  Divider()
  Text(prefs.text("lyricsImportHint")).font(AppFont.subheadline).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
  Button(prefs.text("importLyrics")){subtitlePicker=true}.buttonStyle(SoundButtonStyle(prominent:true)).disabled(packs.installing)
  if let subtitleMessage{Text(subtitleMessage).font(AppFont.callout).foregroundStyle(subtitleFailed ? .red:teal)}
 }.padding(24).frame(maxWidth:.infinity,alignment:.leading)}.navigationTitle(prefs.text("packs")).toolbar{Button(prefs.text("done")){dismiss()}}.interactiveDismissDisabled(packs.installing)
 .fileImporter(isPresented:$picker,allowedContentTypes:[.zip,UTType(filenameExtension:"rar") ?? .archive]){result in switch result{case .success(let u):packs.importArchive(u);case .failure(let error):packs.failed=true;packs.message=prefs.text("importFailed")+"\n"+localizedUIError(error)}}
 .sheet(isPresented:$downloadList){PackDownloadList(packs:packs)}
 .fileImporter(isPresented:$folderPicker,allowedContentTypes:[.folder]){result in switch result{case .success(let u):packs.importFolder(u);case .failure(let error):packs.failed=true;packs.message=prefs.text("importFailed")+"\n"+localizedUIError(error)}}
 .fileImporter(isPresented:$subtitlePicker,allowedContentTypes:[.json]){result in do{let count=try SubtitleStore.importFile(result.get(),songs:packs.songs);subtitleFailed=false;subtitleMessage=prefs.text("lyricsImported")+" (\(count))"}catch{subtitleFailed=true;subtitleMessage=prefs.text("lyricsInvalid")}}
 }}
}
struct PackDownloadList:View {
 @ObservedObject var packs:PackStore
 @ObservedObject private var downloads=PackDownloads.shared
 @ObservedObject private var prefs=Preferences.shared
 @Environment(\.dismiss) private var dismiss
 @State private var link=""
 private func bytes(_ count:Int64)->String{ByteCountFormatter.string(fromByteCount:max(0,count),countStyle:.file)}
 private func status(_ task:PackDownload)->String{
  let keys=["downloading":"downloadingPack","paused":"downloadPaused","queued":"downloadQueued","importing":"downloadImporting","installed":"downloadInstalled","failed":"downloadFailed","cancelled":"downloadCancelled"]
  return prefs.text(keys[task.status] ?? "downloadFailed")
 }
 var body:some View{NavigationStack{ScrollView{VStack(alignment:.leading,spacing:20){
  Text(prefs.text("downloadListHint")).font(AppFont.callout).foregroundStyle(.secondary)
  TextField(prefs.text("httpsPackURL"),text:$link).keyboardType(.URL).textContentType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled().textFieldStyle(.roundedBorder)
  Button(prefs.text("addDownload")){downloads.addLink(link)}.buttonStyle(SoundButtonStyle(prominent:true)).disabled(link.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty || downloads.resolving)
  if downloads.resolving{ProgressView()}
  if let error=downloads.linkError{Text(error).foregroundStyle(.red).font(AppFont.callout)}
  if !downloads.available.isEmpty{DisclosureGroup(prefs.text("releaseAssets")+" (\(downloads.available.count))"){
   ForEach(downloads.available){pack in
    Button{downloads.add(pack.browser_download_url)}label:{VStack(alignment:.leading,spacing:5){Text(pack.name).font(AppFont.body);Text(bytes(pack.size)).font(AppFont.caption).foregroundStyle(.secondary)}}.buttonStyle(SoundButtonStyle())
   }
  }}
  if downloads.items.isEmpty{Text(prefs.text("emptyDownloads")).foregroundStyle(.secondary)}
  ForEach(downloads.items){task in VStack(alignment:.leading,spacing:10){
   Text(task.name).font(AppFont.headline).lineLimit(3)
   Text(task.url.host ?? "").font(AppFont.caption).foregroundStyle(.secondary)
   HStack{Text(status(task));Spacer();if task.status=="downloading"{Text(bytes(Int64(task.speed))+"/s").monospacedDigit()}}.font(AppFont.callout)
   if ["downloading","paused"].contains(task.status){
    if let fraction=task.fraction{ProgressView(value:fraction);Text("\(Int(fraction*100))% · "+bytes(task.received)+" / "+bytes(task.expected)).font(AppFont.caption).monospacedDigit()}
    else{ProgressView();Text(bytes(task.received)).font(AppFont.caption).monospacedDigit()}
   }
   if task.status=="importing"{ProgressView();Text(packs.progress).font(AppFont.caption)}
   if let error=task.error{Text(error).foregroundStyle(.red).font(AppFont.callout).textSelection(.enabled)}
   HStack{
    if task.status=="downloading"{Button(prefs.text("pauseDownload")){downloads.pause(task.id)}}
    if ["paused","failed","cancelled"].contains(task.status){Button(prefs.text("resumeDownload")){downloads.retry(task.id)}}
    if ["downloading","paused","queued"].contains(task.status){Button(prefs.text("cancelDownload")){downloads.cancel(task.id)}}
    if ["installed","failed","cancelled"].contains(task.status){Button(prefs.text("removeDownload")){downloads.remove(task.id)}}
   }.buttonStyle(SoundButtonStyle())
  }.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(.thinMaterial,in:RoundedRectangle(cornerRadius:16))}
 }.padding(20)}.navigationTitle(prefs.text("downloads")).toolbar{Button(prefs.text("done")){dismiss()}}.onAppear{downloads.bind(packs)}}}
}
struct MVPlayerView:UIViewRepresentable {
 let player:AVPlayer;var fill=false
 final class Surface:UIView{override class var layerClass:AnyClass{AVPlayerLayer.self};var playerLayer:AVPlayerLayer{layer as! AVPlayerLayer}}
 func makeUIView(context:Context)->Surface{let v=Surface();v.playerLayer.player=player;v.playerLayer.videoGravity = fill ? .resizeAspectFill:.resizeAspect;return v}
 func updateUIView(_ view:Surface,context:Context){view.playerLayer.player=player;view.playerLayer.videoGravity=fill ? .resizeAspectFill:.resizeAspect}
}
struct MVSessionView:View {
 let songs:[Song];let karaoke:Bool;let lyrics:Bool
 @State private var order:MVPlaybackOrder
 @State private var session=UUID()
 init(songs:[Song],karaoke:Bool,loop:Bool,lyrics:Bool){self.songs=songs;self.karaoke=karaoke;self.lyrics=lyrics;_order=State(initialValue:MVPlaybackOrder(songIDs:songs.map(\.id),loop:loop))}
 var body:some View {if let id=order.currentID,let song=songs.first(where:{$0.id==id}){GameView(song:song,difficulty:.normal,mode:karaoke ? .karaoke:.mv,lyricsOverride:lyrics,playbackComplete:{if order.advance() != nil{session=UUID();return true};return false},restartPlayback:{order.restart();session=UUID()}).id(session)}}
}
struct GameView:View {
 @Environment(\.dismiss) private var dismiss
 @Environment(\.scenePhase) private var scenePhase
 @Environment(\.horizontalSizeClass) private var horizontal
 @Environment(\.verticalSizeClass) private var vertical
 @ObservedObject private var prefs=Preferences.shared
 @AppStorage("showLyrics") private var storedShowLyrics=true
 @AppStorage("handiness") private var handValue=Handiness.right.rawValue
 @AppStorage("selectionStyle") private var selectionStyle=SelectionStyle.legacy.rawValue
 @StateObject private var game:GameEngine
 @State private var scrubPosition=0.0
 let lyricsOverride:Bool?;let playbackComplete:(()->Bool)?;let restartPlayback:(()->Void)?
 init(song:Song,difficulty:Difficulty,mode:PlayMode,lyricsOverride:Bool?=nil,playbackComplete:(()->Bool)?=nil,restartPlayback:(()->Void)?=nil){_game=StateObject(wrappedValue:GameEngine(song:song,difficulty:difficulty,mode:mode));self.lyricsOverride=lyricsOverride;self.playbackComplete=playbackComplete;self.restartPlayback=restartPlayback}
 var showLyrics:Bool {lyricsOverride ?? storedShowLyrics}
 func restart(){if let restartPlayback{restartPlayback()}else{game.start()}}
 var hand:Handiness {Handiness(rawValue:handValue) ?? .right}
 var legacyInterlude:Bool {selectionStyle == SelectionStyle.legacy.rawValue && game.mini}
 var bigScreen:Bool { UIDevice.current.userInterfaceIdiom == .pad || (horizontal == .regular && vertical == .regular) }
 var body:some View {GeometryReader { geo in
  presentation(geo).frame(width:geo.size.width,height:geo.size.height).environment(\.compactGameplayEffects,UIDevice.current.userInterfaceIdiom == .phone && geo.size.width>geo.size.height && geo.size.height<450)
   .overlay {
    if let error=game.error {panel(prefs.text("mediaFailed"),error)}
    else if game.preparing {VStack{ProgressView();Text(prefs.text("preparing"))}.frame(maxWidth:.infinity,maxHeight:.infinity).background(backdrop)}
    else if game.finished {ResultEntrance(duration:game.mode == .play ? ResultCountup.totalDuration(resultValues):0){elapsed in results(elapsed:elapsed)}}
    else if game.paused && game.mode == .play {pauseScreen}
   }
 }.background(StageBackground()).buttonStyle(SoundButtonStyle()).screenTransition(game:true,waiting:game.preparing).task{do{try await Task.sleep(for:SceneLoading.minimumDuration);guard !Task.isCancelled else{return};game.start()}catch{}}.onDisappear{game.stop()}.onChange(of:scenePhase){_,p in if p == .background{game.pause()}}.onChange(of:game.finished){_,finished in if finished && game.mode != .play && playbackComplete?() != true{MenuMusic.shared.play("BGM05")}} }
 @ViewBuilder func presentation(_ geo:GeometryProxy)->some View {
  if #available(iOS 27.1,*),bigScreen,let region=geo.reservedRegions(kind:.division).first(where:{$0.isActive}) {
   let r=region.frame
   if r.width>r.height {
    tabletopPresentation(geo,division:r)
   } else {
    HStack(spacing:0){viewing(height:max(180,geo.size.height-160),independentLyrics:true).padding(18).frame(width:max(240,r.minX));Color.clear.frame(width:r.width+16);rightPanel.frame(maxWidth:.infinity).padding(18)}
   }
  } else if geo.size.width>geo.size.height {
   HStack(spacing:bigScreen ? 28:14){
    if !bigScreen && hand.isLeft {rightPanel.frame(width:min(470,geo.size.width*0.46));viewing(height:max(140,geo.size.height-100),independentLyrics:true).frame(maxWidth:.infinity)}
    else {viewing(height:max(140,geo.size.height-100),independentLyrics:true).frame(maxWidth:.infinity);rightPanel.frame(width:min(470,geo.size.width*0.46))}
   }.padding(bigScreen ? 22:16)
  } else {
   if UIDevice.current.userInterfaceIdiom == .pad && game.mode == .play {tabletPortrait(geo)}
   else if game.mode == .play {
    ZStack{MVPlayerView(player:game.player,fill:true).ignoresSafeArea();LinearGradient(colors:[.black.opacity(0.55),.clear,.black.opacity(0.25)],startPoint:.top,endPoint:.bottom).ignoresSafeArea()
     VStack(spacing:8){portraitScoreBar;portraitHeader;Spacer(minLength:12);if showLyrics{Text(game.lyric).font(AppFont.subheadline).multilineTextAlignment(.center).shadow(color:.black,radius:3)};ProgressView(value:min(max(game.clock/game.duration,0),1)).tint(teal)
      let inputHeight=max(180,min(320,geo.size.height*0.56-134))
      VStack(spacing:6){
       noteLane.frame(height:62);comboStatus;nextInputStatus
       HStack(alignment:.bottom,spacing:12){
        if !hand.isLeft && game.difficulty != .breakLimit && !legacyInterlude {MicrophoneGauge(value:game.tally.gauge/256).frame(width:inputHeight*146/388,height:inputHeight).opacity(game.normalAlpha)}
        inputArea(maxWidth:.infinity,maxHeight:inputHeight).frame(maxWidth:.infinity).overlay(alignment:hand.isLeft ? .bottomLeading:.bottomTrailing){portraitPause}
        if hand.isLeft && game.difficulty != .breakLimit && !legacyInterlude {MicrophoneGauge(value:game.tally.gauge/256).frame(width:inputHeight*146/388,height:inputHeight).opacity(game.normalAlpha)}
       }.frame(height:inputHeight)
      }
     }.padding(.horizontal,12).padding(.vertical,10).frame(maxWidth:500).frame(maxWidth:.infinity,maxHeight:.infinity)
    }
   } else {VStack(spacing:9){header;movie(height:max(200,geo.size.height*0.72),lyrics:true);playbackProgress;controls}.padding(.horizontal,18).padding(.vertical,10).frame(maxWidth:700).frame(maxWidth:.infinity,maxHeight:.infinity)}
  }
 }
 @ViewBuilder func tabletopPresentation(_ geo:GeometryProxy,division:CGRect)->some View {
  let topHeight=max(120,division.minY),lowerHeight=max(120,geo.size.height-division.maxY)
  VStack(spacing:0){
   movie(height:topHeight-12,lyrics:true).padding(.horizontal,12).padding(.vertical,6)
    .overlay(alignment:.topLeading){Button{game.stop();dismiss()}label:{Image(systemName:"chevron.left").font(AppFont.title3).frame(width:44,height:44).background(.ultraThinMaterial,in:Circle())}.padding(18).accessibilityLabel(prefs.text("back"))}
    .frame(height:topHeight)
   Color.clear.frame(height:division.height).overlay {if game.autoplay {Text("AUTO PLAY").font(AppFont.caption2).foregroundStyle(teal)}}
   if game.mode == .play {
    HStack(alignment:.bottom,spacing:12){
     if game.difficulty != .breakLimit && !legacyInterlude {MicrophoneGauge(value:game.tally.gauge/256).frame(width:min(320,lowerHeight-32)*146/388,height:min(320,lowerHeight-32)).opacity(game.normalAlpha)}
     VStack(spacing:6){noteLane.frame(height:42);if legacyInterlude{Color.clear}else{inputArea(maxWidth:420,maxHeight:max(90,lowerHeight-76)).frame(maxWidth:.infinity)}}.frame(maxWidth:.infinity)
     VStack(alignment:.trailing,spacing:10){Text(prefs.text("score")).font(AppFont.caption2).foregroundStyle(.secondary);OriginalNumber(value:game.score,height:23);Text(prefs.text("combo")).font(AppFont.caption2).foregroundStyle(.secondary);OriginalNumber(value:game.combo,height:23,family:"combonumber");Button{game.togglePause()}label:{Image(systemName:"pause.fill").frame(width:44,height:44).background(.ultraThinMaterial,in:Circle())}.accessibilityLabel(prefs.text("pause"))}.frame(width:96)
    }.padding(14).frame(height:lowerHeight).overlay{if legacyInterlude{inputArea(maxWidth:420,maxHeight:max(90,lowerHeight-76)).padding(.top,48)}}
   }else{VStack(spacing:10){header;playbackProgress;if showLyrics{lyricsPanel}}.padding(16).frame(height:lowerHeight)}
  }
 }
 var portraitHeader:some View {HStack{Button{game.stop();dismiss()}label:{Image(systemName:"chevron.left").frame(width:32,height:40)};Text(game.song.title).font(AppFont.caption).lineLimit(1);Spacer();Text(game.autoplay ? "AUTO PLAY":game.difficulty.localizedLabel).font(AppFont.caption2).foregroundStyle(game.difficulty.color)}.foregroundStyle(.white)}
 var portraitPause:some View {Button{game.togglePause()}label:{OriginalSprite(name:"pausebutton").frame(width:28,height:28)}.disabled(game.preparing||game.finished).accessibilityLabel(prefs.text("pause"))}
 var portraitScoreBar:some View {HStack(alignment:.top){HStack(spacing:6){Text(prefs.text("highScore")).font(AppFont.caption2);OriginalNumber(value:UserDefaults.standard.integer(forKey:game.bestKey),height:16,family:"highscore")};Spacer();OriginalNumber(value:game.score,height:28)}.shadow(color:.black,radius:3)}
 @ViewBuilder func tabletPortrait(_ g:GeometryProxy)->some View {
  let keyboardHeight=min(690,g.size.height*0.55)
  ZStack{MVPlayerView(player:game.player,fill:true).ignoresSafeArea();LinearGradient(colors:[.black.opacity(0.45),.clear,.black.opacity(0.2)],startPoint:.top,endPoint:.bottom).ignoresSafeArea()
   VStack(spacing:12){
    HStack(alignment:.top){VStack(alignment:.leading,spacing:4){Text(prefs.text("highScore")).font(AppFont.headline);OriginalNumber(value:UserDefaults.standard.integer(forKey:game.bestKey),height:24)};Spacer();OriginalNumber(value:game.score,height:42)}.shadow(color:.black,radius:3)
    HStack{Button{game.stop();dismiss()}label:{HStack{Image(systemName:"chevron.left");Text(prefs.text("back"))}.font(AppFont.headline).padding(12).background(.black.opacity(0.35))}.accessibilityLabel(prefs.text("back"));Spacer();VStack(alignment:.trailing,spacing:4){Text(game.song.title).font(AppFont.headline).shadow(color:.black,radius:3);if game.autoplay {Text("AUTO PLAY").font(AppFont.caption2).foregroundStyle(teal)}}}
    Spacer(minLength:20)
    if showLyrics{Text(game.lyric).font(AppFont.title3).multilineTextAlignment(.center).shadow(color:.black,radius:3)}
    ProgressView(value:min(max(game.clock/game.duration,0),1)).tint(teal)
    noteLane.frame(height:72)
    HStack(alignment:.bottom,spacing:16){
     if game.difficulty != .breakLimit && !legacyInterlude {MicrophoneGauge(value:game.tally.gauge/256).frame(width:keyboardHeight*146/388,height:keyboardHeight).opacity(game.normalAlpha)}
     VStack(spacing:12){HStack{OriginalNumber(value:game.combo,height:26,family:"combonumber");Text(prefs.text("combo")).font(AppFont.caption);Spacer();Text(String(format:"%02d:%02d",Int(game.clock)/60,Int(game.clock)%60)).monospacedDigit()};inputArea(maxWidth:600,maxHeight:max(1,keyboardHeight-50)).frame(maxWidth:.infinity)}.frame(maxWidth:legacyInterlude ? .infinity:600)
     if !legacyInterlude{tabletPause}
    }.frame(maxWidth:.infinity).overlay(alignment:.bottomTrailing){if legacyInterlude{tabletPause}}
   }.padding(.horizontal,28).padding(.vertical,20)
  }
 }

 var tabletPause:some View {Button{game.togglePause()}label:{OriginalSprite(name:"pausebutton").frame(width:54,height:54).padding(6)}.disabled(game.preparing||game.finished).accessibilityLabel(prefs.text("pause"))}

 var noteLane:some View {NoteLane(notes:game.visible,target:game.normalTarget,effects:game.effects,clock:game.clock,timingStep:game.inputTimingStep,romanMode:prefs.roman,interlude:game.mini,normalAlpha:game.normalAlpha,interludeAlpha:game.interludeAlpha,combo:game.combo,timingHints:prefs.effectiveTimingHints,originalJudgements:prefs.originalJudgements)}

 var header:some View {HStack{Button{game.stop();dismiss()}label:{Image(systemName:"chevron.left").frame(width:44,height:44).contentShape(Rectangle())}.accessibilityLabel(prefs.text("back"));VStack(alignment:.leading){Text(game.song.title).font(AppFont.headline).lineLimit(1);Text(game.mode == .play ? (game.autoplay ? "AUTO PLAY":game.difficulty.localizedLabel):prefs.text(game.mode.rawValue)).font(AppFont.caption2).foregroundStyle(game.mode == .play ? game.difficulty.color:teal)};Spacer();Button{game.togglePause()}label:{Image(systemName:game.paused ? "play.fill":"pause.fill").frame(width:44,height:44).contentShape(Rectangle())}.disabled(game.preparing||game.finished||game.scrubbing).accessibilityLabel(prefs.text(game.paused ? "continue":"paused"))}.foregroundStyle(.white)}
 var hud:some View {VStack(spacing:7){HStack{VStack(alignment:.leading){Text(prefs.text("score")).font(AppFont.caption2).foregroundStyle(.secondary);OriginalNumber(value:game.score,height:27)};Spacer();VStack(alignment:.trailing){Text(prefs.text("combo")).font(AppFont.caption2).foregroundStyle(.secondary);OriginalNumber(value:game.combo,height:27,family:"combonumber")}}
  if game.difficulty != .breakLimit && !legacyInterlude {HStack(spacing:8){Image(systemName:"mic.fill").font(AppFont.caption2).foregroundStyle(teal);ProgressView(value:game.tally.gauge,total:256).tint(game.tally.gauge<64 ? .red:teal);Text("\(Int(game.tally.gauge/256*100))%").font(AppFont.caption2).foregroundStyle(.secondary)}.accessibilityLabel(Preferences.shared.text("microphoneGauge"))}
 }}
 func movie(height:CGFloat,lyrics:Bool)->some View {ZStack(alignment:.bottom){MVPlayerView(player:game.player);if lyrics && showLyrics && !game.lyric.isEmpty{subtitle(game.lyric).padding(10).frame(maxWidth:.infinity).background(.black.opacity(0.65))}}.frame(height:height).background(.black).clipShape(RoundedRectangle(cornerRadius:18))}
 func subtitle(_ original:String)->some View {VStack(spacing:5){Text(original).font(AppFont.subheadline);if let translation=game.translation(of:original){Text(translation).font(AppFont.subheadline).foregroundStyle(.white.opacity(0.9))}}.multilineTextAlignment(.center).foregroundStyle(.white).fixedSize(horizontal:false,vertical:true)}
 func viewing(height:CGFloat,independentLyrics:Bool)->some View {VStack(spacing:12){header;if game.mode == .play{hud};movie(height:max(90,height-(game.mode == .play ? 80:65)),lyrics:true);playbackProgress}}
 @ViewBuilder var playbackProgress:some View {
  if game.mode == .play{ProgressView(value:min(max(game.clock/game.duration,0),1)).tint(teal)}
  else{VStack(spacing:2){
   Slider(value:$scrubPosition,in:0...max(0.01,game.duration),onEditingChanged:{editing in if editing{game.beginScrubbing()}else{game.endScrubbing(at:scrubPosition)}}).onChange(of:game.clock){_,value in if !game.scrubbing{scrubPosition=min(game.duration,max(0,value))}}.tint(teal).disabled(game.preparing||game.finished).accessibilityLabel(prefs.text("playbackPosition")).accessibilityAdjustableAction{direction in game.beginScrubbing();scrubPosition=min(game.duration,max(0,game.clock+(direction == .increment ? 5:-5)));game.endScrubbing(at:scrubPosition)}
   HStack{Text(playbackTime(game.scrubbing ? scrubPosition:game.clock));Spacer();Text(playbackTime(game.duration))}.font(AppFont.caption).foregroundStyle(.white.opacity(0.7))
   if showLyrics,game.lyricTranslation != nil,let source=game.subtitleSource,let url=source.sourceURL.flatMap(URL.init(string:)){Link(source.translator ?? prefs.text("subtitleSource"),destination:url).font(AppFont.caption2).foregroundStyle(teal)}
  }}
 }
 func playbackTime(_ seconds:Double)->String{let value=max(0,Int(seconds));return String(format:"%02d:%02d",value/60,value%60)}
 var rightPanel:some View {VStack(spacing:10){if game.mode == .play{controls}else if showLyrics{lyricsPanel}else{Text(game.song.title).font(AppFont.title2);Spacer();Text(String(format:"%02d:%02d",Int(game.clock)/60,Int(game.clock)%60)).monospacedDigit()}}}
 var lyricsPanel:some View {ScrollViewReader{proxy in ScrollView{LazyVStack(alignment:.leading,spacing:26){ForEach(Array(game.cues.enumerated()).filter{$0.element.parameter.first == "3"},id:\.offset){index,cue in
  let active=cue.time<=game.clock && (game.cues.dropFirst(index+1).first{$0.parameter.first == "3"}?.time ?? .infinity)>game.clock
  let original=String(cue.parameter.dropFirst())
  VStack(alignment:.leading,spacing:7){Text(original).font(active ? AppFont.title:AppFont.title3);if let translation=game.translation(of:original){Text(translation).font(active ? AppFont.headline:AppFont.subheadline)}}.foregroundStyle(active ? .white:.secondary).id(index)
 }}.padding(.vertical,80)}.onChange(of:game.lyric){_,_ in if let index=game.cues.lastIndex(where:{$0.time<=game.clock && $0.parameter.first == "3"}){withAnimation{proxy.scrollTo(index,anchor:.center)}}}}}
 var comboStatus:some View {HStack{if game.combo>0{OriginalNumber(value:game.combo,height:18,family:"combonumber");Text(prefs.text("combo")).font(AppFont.caption).foregroundStyle(.yellow)};Spacer();Text(String(format:"%02d:%02d",Int(game.clock)/60,Int(game.clock)%60)).font(AppFont.caption).foregroundStyle(.secondary)}.frame(height:22)}
 var nextInputStatus:some View {HStack{Text(prefs.text(game.mini ? "mini":"next")).font(AppFont.caption).foregroundStyle(.secondary);Spacer();if let n=game.target{Text(n.interlude ? "♪":(n.inputLabel == nil ? String(kanaGroups[n.key].first!):LetterInputMap.groups[n.key])+" "+["●","←","↑","→","↓"][n.direction]+"  "+n.displayText+(n.inputLabel.flatMap{$0 == n.displayText.uppercased() ? nil:" ("+$0+")"} ?? "")).font(AppFont.title3).foregroundStyle(Color.yellow)}}.frame(height:32)}
 @ViewBuilder var controls:some View {
  if game.mode == .play {
   noteLane.frame(height:62)
   comboStatus;nextInputStatus
   inputArea(maxWidth:bigScreen ? 340:.infinity,maxHeight:bigScreen ? 360:.infinity).frame(maxWidth:.infinity,alignment:.center)
  } else {if !bigScreen{Text(String(format:"%02d:%02d / %02d:%02d",Int(game.clock)/60,Int(game.clock)%60,Int(game.duration)/60,Int(game.duration)%60)).font(AppFont.caption).foregroundStyle(.secondary);Spacer(minLength:0)}}
 }
 func inputArea(maxWidth:CGFloat,maxHeight:CGFloat)->some View {
  ZStack {
   InterludeInput(clock:game.clock,autoHitAt:game.autoplay ? game.effects.last(where:{$0.note.interlude})?.time:nil,mediaTime:{game.player.currentTime().seconds}){down in game.input(key:-1,direction:0,down:down)}.opacity(game.interludeAlpha).allowsHitTesting(game.mini && game.interludeAlpha>0).accessibilityHidden(!game.mini).accessibilityLabel(prefs.text("mini"))
   Group {
    if game.song.inputLanguage == .english || game.song.inputLanguage == .chinese {
     LetterKeyboard(language:game.song.inputLanguage!,guides:game.guides,clock:game.clock,mediaTime:{game.player.currentTime().seconds}){key,direction,down in game.input(key:key,direction:direction,down:down)}
    }else{KanaKeyboard(guides:game.guides,clock:game.clock,romanMode:prefs.roman,mediaTime:{game.player.currentTime().seconds}){key,direction,down in game.input(key:key,direction:direction,down:down)}}
   }.opacity(game.normalAlpha).allowsHitTesting(!game.mini && game.normalAlpha>0).accessibilityHidden(game.mini)
  }.frame(maxWidth:maxWidth,maxHeight:maxHeight)
 }

 var resultValues:[Int] {[game.tally.totalNotes,game.maxCombo]+Judgement.allCases.filter{$0 != .none}.reversed().map{game.tally.counts[$0.rawValue]}+[game.tally.interludeSuccess,game.tally.stage,game.tally.bonus,game.score]}
 func results(elapsed:Double)->some View {GeometryReader{g in
  let compact=g.size.height<760
  let numberHeight:CGFloat=compact ? 17:22
  ScrollView{VStack(spacing:compact ? 8:14){
   ArtworkScreenHeading(title:"RESULT",expanded:!compact,color:Color(hex:0xA8EDCD))
   if game.autoplay {Text("AUTO PLAY · "+prefs.text("testResult")).font(AppFont.caption).foregroundStyle(.white)}
   HStack(spacing:18){if let image=game.song.image{Image(uiImage:image).resizable().scaledToFit().frame(width:compact ? 60:88,height:compact ? 60:88)};VStack(spacing:0){if let title=game.song.titleImage{Image(uiImage:title).resizable().scaledToFit().frame(height:compact ? 44:70)}else{Text(game.song.title).font(AppFont.headline)};HStack(spacing:2){ForEach(0..<(Int(game.song.level(game.difficulty)) ?? 0),id:\.self){_ in OriginalSprite(name:"difficultystar_01").frame(width:18,height:18)}}}.frame(maxWidth:.infinity);if game.failedResult{OriginalSprite(name:"failed").frame(width:90,height:44)}}
   if game.mode == .play {
    VStack(spacing:compact ? 4:9){
     Text(game.difficulty.localizedLabel).font(AppFont.headline).frame(maxWidth:.infinity).padding(.vertical,7).background(Color(hex:0x163A50).opacity(0.7),in:Capsule())
     HStack(alignment:.top,spacing:14){VStack(spacing:compact ? 4:8){resultRow(prefs.text("totalNotes"),game.tally.totalNotes,height:numberHeight,elapsed:ResultCountup.rowElapsed(elapsed,slot:0,values:resultValues));resultRow(prefs.text("maxCombo"),game.maxCombo,height:numberHeight,elapsed:ResultCountup.rowElapsed(elapsed,slot:1,values:resultValues))};ZStack(alignment:.bottomLeading){OriginalRank(rank:game.tally.rank).frame(width:compact ? 75:110,height:compact ? 65:90);if game.newRecord{OriginalSprite(name:"newrecord").frame(width:compact ? 55:85,height:compact ? 55:85).offset(x:-14,y:14)}}}
     VStack(spacing:compact ? 3:6){ForEach(Judgement.allCases.filter{$0 != .none}.reversed(),id:\.rawValue){j in resultRow(j.localizedLabel,game.tally.counts[j.rawValue],height:numberHeight,elapsed:ResultCountup.rowElapsed(elapsed,slot:7-j.rawValue,values:resultValues)).padding(.horizontal,10).background{Image(uiImage:originalImage("textbar_00") ?? UIImage()).resizable()}};resultRow("♪",game.tally.interludeSuccess,height:numberHeight,elapsed:ResultCountup.rowElapsed(elapsed,slot:7,values:resultValues)).padding(.horizontal,10).background{Image(uiImage:originalImage("textbar_00") ?? UIImage()).resizable()}}.padding(.horizontal,compact ? 18:32)
     VStack(spacing:compact ? 3:7){resultRow(prefs.text("stageScore"),game.tally.stage,height:numberHeight,elapsed:ResultCountup.rowElapsed(elapsed,slot:8,values:resultValues));resultRow(prefs.text("comboBonus"),game.tally.bonus,height:numberHeight,elapsed:ResultCountup.rowElapsed(elapsed,slot:9,values:resultValues));resultRow(prefs.text("totalScore"),game.score,height:numberHeight,elapsed:ResultCountup.rowElapsed(elapsed,slot:10,values:resultValues))}.padding(.top,compact ? 2:8)
    }.padding(compact ? 14:22).background(LegacyResultPanel())
   }else{Text(prefs.text("ended")).font(AppFont.title2)}
   HStack(spacing:14){Button{game.stop();dismiss()}label:{LegacyButton(title:prefs.text("back"),height:44)};Button{restart()}label:{LegacyButton(title:prefs.text("restart"),height:44)}}
  }.foregroundStyle(.white).font(AppFont.system(size:compact ? 15:19,weight:.semibold)).shadow(color:.black.opacity(0.55),radius:1,x:1,y:1).padding(18).frame(maxWidth:compact ? 600:700).frame(maxWidth:.infinity).frame(minHeight:max(0,g.size.height-36))}.scrollIndicators(.hidden)
 }.background(LegacyBackground(name:"bg_result-clean"))}
 func resultRow(_ title:String,_ value:Int,height:CGFloat,elapsed:Double)->some View {HStack{Text(title);Spacer(minLength:12);ResultNumber(value:value,height:height,elapsed:elapsed)}}
 var pauseScreen:some View {GeometryReader{g in
  let wide=g.size.width>g.size.height,compact=wide && g.size.height<450
  let buttonHeight:CGFloat=compact ? 44:min(88,max(54,wide ? g.size.height*0.12:g.size.width*0.09))
  ScrollView{VStack(spacing:compact ? 12:24){
   Text(prefs.text("paused")).font(LegacyUIFont.title(prefs.text("paused"),size:compact ? 22:30)).tracking(5).foregroundStyle(.white.opacity(0.8))
   if wide && game.mode == .play {HStack(alignment:.center,spacing:compact ? 18:30){pauseButtons(height:buttonHeight).frame(width:min(420,(g.size.width-(compact ? 50:80))*0.37));inputTimingControl(compact:compact).frame(maxWidth:.infinity)}.frame(maxWidth:1000)}
   else {pauseButtons(height:buttonHeight).frame(maxWidth:game.mode == .play ? 540:600);if game.mode == .play{inputTimingControl().frame(maxWidth:640)}}
  }.padding(.horizontal,compact ? 16:24).padding(.vertical,compact ? 12:24).frame(maxWidth:.infinity,minHeight:g.size.height)}
 }.background{LinearGradient(colors:[.black,Color(hex:0x05091D),Color(hex:0x060E3B)],startPoint:.top,endPoint:.bottom).ignoresSafeArea()}}
 func pauseButtons(height:CGFloat)->some View {VStack(spacing:12){
  Button{game.togglePause()}label:{LegacyButton(title:prefs.text("resume"),height:height)}
  Button{restart()}label:{LegacyButton(title:prefs.text("retry"),height:height)}
  Button{game.stop();dismiss()}label:{LegacyButton(title:prefs.text("musicSelect"),height:height)}
 }}
 func inputTimingControl(compact:Bool=false)->some View {VStack(spacing:compact ? 6:12){
  HStack{Text(prefs.text("inputTiming")).font(AppFont.system(size:compact ? 15:18)).lineLimit(1).minimumScaleFactor(0.65);Spacer(minLength:6);Button(prefs.text("resetTiming")){game.setInputTiming(0)}.font(AppFont.system(size:compact ? 12:16)).lineLimit(1).minimumScaleFactor(0.7).disabled(game.inputTimingStep==0)}
  HStack(spacing:compact ? 8:20){
   Button{game.setInputTiming(game.inputTimingStep-1)}label:{Image(systemName:"minus").font(AppFont.title3).frame(width:44,height:44).background(.white.opacity(0.09),in:Circle())}.disabled(game.inputTimingStep == -10).accessibilityLabel("−")
   VStack(spacing:4){Text(String(format:game.inputTimingMS==0 ? "%.1f":"%+.1f",game.inputTimingMS)+" "+prefs.text("milliseconds")).font(AppFont.system(size:compact ? 25:34,weight:.semibold)).monospacedDigit().lineLimit(1).minimumScaleFactor(0.6);Text(String(format:prefs.text("timingPosition"),Double(game.inputTimingStep))).font(AppFont.system(size:compact ? 11:13)).lineLimit(1).minimumScaleFactor(0.6).foregroundStyle(.white.opacity(0.7))}.frame(maxWidth:.infinity)
   Button{game.setInputTiming(game.inputTimingStep+1)}label:{Image(systemName:"plus").font(AppFont.title3).frame(width:44,height:44).background(.white.opacity(0.09),in:Circle())}.disabled(game.inputTimingStep == 10).accessibilityLabel("+")
  }
  Slider(value:Binding<Double>(get:{Double(game.inputTimingStep)},set:{game.setInputTiming(Int($0.rounded()))}),in:-10...10,step:1,onEditingChanged:{editing in if !editing{SoundEffects.shared.play("SE02_01")}}).tint(Color(hex:0x74ECDF)).accessibilityLabel(prefs.text("inputTiming")).accessibilityValue(String(format:"%.1f",game.inputTimingMS)+" "+prefs.text("milliseconds"))
  HStack{Text("−10");Spacer();Text("−5");Spacer();Text("0");Spacer();Text("+5");Spacer();Text("+10")}.font(AppFont.system(size:compact ? 11:13)).foregroundStyle(.white.opacity(0.5)).padding(.horizontal,6)
  Text(prefs.text("timingExplanation")).font(AppFont.system(size:compact ? 11:15)).foregroundStyle(.white.opacity(0.7)).fixedSize(horizontal:false,vertical:true).frame(maxWidth:.infinity,alignment:.leading)
 }.foregroundStyle(.white).padding(compact ? 12:20).background(.white.opacity(0.045),in:RoundedRectangle(cornerRadius:18)).overlay(RoundedRectangle(cornerRadius:18).stroke(Color(hex:0x74ECDF).opacity(0.25),lineWidth:1))}
 var actions:some View {VStack(spacing:18){if game.paused && !game.finished{Button(prefs.text("continue")){game.togglePause()}.buttonStyle(SoundButtonStyle(prominent:true)).tint(teal)};Button(prefs.text("restart")){restart()}.buttonStyle(SoundButtonStyle(prominent:true)).tint(teal);Button(prefs.text("back")){game.stop();dismiss()}}}
 func panel(_ title:String,_ detail:String)->some View {VStack(spacing:24){Text(title).font(AppFont.largeTitle);Text(detail).multilineTextAlignment(.center);actions}.padding(24).frame(maxWidth:.infinity,maxHeight:.infinity).background(backdrop)}
}
struct MicrophoneGauge:View {
 let value:Double
 var body:some View {GeometryReader{g in
  VStack(spacing:8){Image(systemName:"waveform").foregroundStyle(teal);GeometryReader{v in ZStack(alignment:.bottom){Capsule().fill(.white.opacity(0.12));Capsule().fill(teal.gradient).frame(height:v.size.height*min(1,max(0,value)))}}}.padding(8).frame(width:min(44,g.size.width)).frame(maxWidth:.infinity,maxHeight:.infinity)
 }.accessibilityLabel(Preferences.shared.text("microphoneGauge")).accessibilityValue("\(Int(min(1,max(0,value))*100))%")}
}
struct LegacyResultPanel:View {var body:some View {RoundedRectangle(cornerRadius:24).fill(.ultraThinMaterial).overlay{RoundedRectangle(cornerRadius:24).stroke(teal.opacity(0.35),lineWidth:1)}}}
private struct CompactGameplayEffectsKey:EnvironmentKey {static let defaultValue=false}
extension EnvironmentValues {var compactGameplayEffects:Bool {get{self[CompactGameplayEffectsKey.self]}set{self[CompactGameplayEffectsKey.self]=newValue}}}
struct NoteLane:View {
 @Environment(\.compactGameplayEffects) private var compactEffects
 let notes:[Note];let target:Note?;let effects:[GameplayEffect];let clock:Double;let timingStep:Int;let romanMode:Bool;let interlude:Bool;let normalAlpha:Double;let interludeAlpha:Double;let combo:Int;let timingHints:Bool;let originalJudgements:Bool
 @AppStorage("fullRoman") private var fullRoman=false
 var style:KeyboardStyle {KeyboardStyle.selected(roman:romanMode,full:fullRoman)}
 var body:some View {GeometryReader{g in
  let diameter=g.size.height;let targetX=max(32,min(72,g.size.width*0.105));let centerY=diameter/2
  ZStack(alignment:.topLeading){
   ZStack {
    ScrollingRail(clock:clock,rainbow:OriginalEffects.rainbow(combo:combo)).opacity(normalAlpha*0.7)
    ForEach(notes){note in
     let frames=max(1,OriginalRules.justTick(note,step:timingStep)-OriginalRules.baseTick(note))
     let remaining=OriginalRules.justTick(note,step:timingStep)-OriginalRules.tick(clock)
     laneGlyph(note,size:diameter).opacity(note.interlude ? interludeAlpha:normalAlpha).position(x:targetX+CGFloat(remaining)/CGFloat(frames)*(g.size.width-targetX),y:centerY)
    }
   }.frame(width:g.size.width,height:diameter).clipped()
   if normalAlpha>0 {
    ForEach(0..<OriginalEffects.whirlLayers(combo:combo),id:\.self){layer in
     OriginalSprite(name:layer==0 ? "insidewhirl":"outsidewhirl").frame(width:diameter*(layer==0 ? 1:1.6),height:diameter*(layer==0 ? 1:1.6)).rotationEffect(.degrees(-Double(OriginalRules.tick(clock))*[17.0,13.0,12.0][layer])).opacity(normalAlpha*(layer==0 ? 0.75:0.5)).position(x:targetX,y:centerY)
    }
   }
   ZStack{OriginalSprite(name:"charactercircle_int").opacity(interludeAlpha);OriginalSprite(name:"charactercircle").opacity(normalAlpha)}.frame(width:diameter,height:diameter).position(x:targetX,y:centerY)
   if let target,normalAlpha>0,OriginalRules.baseTick(target)<=OriginalRules.tick(clock),OriginalRules.tick(clock)<=OriginalRules.justTick(target,step:timingStep) {
    OriginalSprite(name:String(format:"inputguide_%02d",KeyboardStyle.guideSprite(direction:target.direction))).frame(width:diameter*0.7,height:diameter*0.7).opacity(normalAlpha).position(x:targetX,y:centerY)
   }
   ForEach(effects){effect in
    let age=max(0,clock-effect.time);let pulseFrame=OriginalVisuals.frame(age:age,lifetime:10)
    let frame=OriginalVisuals.frame(age:age,lifetime:20)
    if !compactEffects && effect.pulse && pulseFrame<10 {
     OriginalSprite(name:"ripple").frame(width:diameter,height:diameter).scaleEffect(OriginalVisuals.pulseScale(frame:pulseFrame,combo:effect.combo)).opacity(OriginalVisuals.opacity(frame:pulseFrame,lifetime:10)).position(x:targetX,y:centerY)
    }
    if effect.pulse {
     ForEach(0..<OriginalEffects.fireworksLayers(combo:effect.combo,interlude:effect.note.interlude,frame:pulseFrame),id:\.self){layer in
      OriginalSprite(name:["fireworks_mik_01","fireworks_mik_00","fireworks_mik_02"][layer]).frame(width:diameter,height:diameter).scaleEffect(OriginalVisuals.pulseScale(frame:pulseFrame,combo:effect.combo)*OriginalEffects.fireworksScale(layer:layer,combo:effect.combo)).opacity(OriginalVisuals.opacity(frame:pulseFrame,lifetime:10)*0.5).position(x:targetX,y:centerY)
     }
    }
    if frame<20 {
     effectGlyph(effect,size:diameter,frame:frame).scaleEffect(compactEffects ? 0.75:OriginalVisuals.resultScale(frame:frame)).scaleEffect(x:1,y:compactEffects || originalJudgements ? 1:OriginalVisuals.resultStretch(frame:frame)).opacity(OriginalVisuals.opacity(frame:frame,lifetime:20)).position(x:compactEffects ? max(targetX,diameter*0.65):targetX,y:compactEffects ? centerY:centerY+OriginalVisuals.resultOffset(frame:frame,interlude:effect.note.interlude)*diameter/120)
    }
   }
  }.frame(width:g.size.width,height:g.size.height).allowsHitTesting(false)
 }}
 @ViewBuilder func laneGlyph(_ note:Note,size:CGFloat)->some View {
  if note.interlude {
   OriginalSprite(name:note.playable ? "quaver_00":"quaver_03").frame(width:size*0.7,height:size*0.78).rotation3DEffect(.degrees(Double(OriginalRules.tick(clock)-OriginalRules.baseTick(note))*21),axis:(x:0,y:1,z:0),perspective:0)
  }else{
   ZStack{if note.playable{OriginalSprite(name:"charactercircle").opacity(0.7)};NoteCharacter(kana:note.displayText,style:note.inputLabel == nil ? style:.original,active:note.playable,inputLabel:note.inputLabel).padding(size*0.16).opacity(note.playable ? 1:0.32).overlay{if note.playable && note.crimax && combo>=100 {let rgb=OriginalEffects.rainbowRGB[OriginalEffects.rainbowColorIndex(note:note,time:clock)];Color(red:rgb[0]/255,green:rgb[1]/255,blue:rgb[2]/255).mask{NoteCharacter(kana:note.displayText,style:note.inputLabel == nil ? style:.original,active:note.playable,inputLabel:note.inputLabel).padding(size*0.16)}}}}.frame(width:size,height:size)
  }
 }
 @ViewBuilder func effectGlyph(_ effect:GameplayEffect,size:CGFloat,frame:Int)->some View {
  if effect.note.interlude {OriginalSprite(name:"quaver_01").frame(width:size*0.8,height:size*0.9)}
  else if originalJudgements {ZStack{
   OriginalSprite(name:String(format:"afterimage_%02d",5-effect.result.rawValue)).frame(width:size*102/120,height:size*102/120).scaleEffect(x:OriginalVisuals.resultStretch(frame:frame),y:1)
   OriginalSprite(name:String(format:"evaluation_%02d",5-effect.result.rawValue)).frame(width:size*142/120,height:size*69/120)
  }}
  else {VStack(spacing:1){Text(effect.result.localizedLabel).font(AppFont.system(size:size*0.36,weight:.bold)).foregroundStyle(effect.result.color);if timingHints && !effect.timingHint.isEmpty{Text(Preferences.shared.text(effect.timingHint=="FAST" ? "fast":"late")).font(AppFont.system(size:size*0.16,weight:.bold)).foregroundStyle(effect.timingHint=="FAST" ? Color(hex:0x64B5FF):Color(hex:0xFF82BD))}}.fixedSize().shadow(color:.black,radius:2)}
 }
}
struct NoteCharacter:View {
 let kana:String;let style:KeyboardStyle;var active=true;var inputLabel:String?=nil
 var body:some View {GeometryReader{g in VStack(spacing:0){Text(style == .fullRoman ? roman(kana).capitalized:kana.uppercased()).font(.system(size:min(g.size.width,g.size.height)*(inputLabel != nil && inputLabel != kana.uppercased() ? 0.59:0.84),weight:.bold,design:.rounded)).lineLimit(1).minimumScaleFactor(0.15);if let inputLabel,inputLabel != kana.uppercased(){Text(inputLabel).font(.system(size:min(g.size.width,g.size.height)*0.23,weight:.semibold,design:.monospaced))}}.foregroundStyle(active ? .white:.gray).frame(maxWidth:.infinity,maxHeight:.infinity)}}
}
struct InterludeInput:View {
 let clock:Double;let autoHitAt:Double?;let mediaTime:()->Double;let input:(Double?)->Void
 @State private var downTime:Double?;@State private var touching=false;@State private var releasedAt = -10.0
 var body:some View {
  OriginalSprite(name:touching || OriginalVisuals.keyFlash(time:clock,releasedAt:autoHitAt ?? releasedAt) ? "flickguide_int_on":"flickguide_int_off").contentShape(Rectangle()).accessibilityAddTraits(.isButton).accessibilityAction{input(nil)}
   .gesture(DragGesture(minimumDistance:0).onChanged{_ in if !touching{downTime=mediaTime()};touching=true}.onEnded{_ in input(downTime);releasedAt=mediaTime();touching=false;downTime=nil})
 }
}
struct ScrollingRail:View {
 let clock:Double;let rainbow:Bool
 var body:some View {GeometryReader{g in let width=max(1,g.size.width)
  if rainbow {
   let offset=CGFloat((Double(OriginalRules.tick(clock)*32).truncatingRemainder(dividingBy:640))/640)*width
   HStack(spacing:0){ForEach(0..<2){_ in Image(uiImage:originalImage("rail_01") ?? UIImage()).resizable().frame(width:width,height:g.size.height)}}.offset(x:-offset).frame(width:width,alignment:.leading).clipped()
  }else{Image(uiImage:originalImage("rail_00") ?? UIImage()).resizable().frame(width:width,height:g.size.height)}
 }}
}
struct KanaKeyboard:View {
 let guides:[PanelGuideHint];let clock:Double;let romanMode:Bool;let mediaTime:()->Double;let input:(Int,Int,Double?)->Void
 @State private var activeKey:Int?
 var body:some View{GeometryReader{g in
  let width=max(1,min((g.size.width-12)/3,(g.size.height-18)/4*127/108))
  let height=width*108/127
  VStack(spacing:6){ForEach(0..<3){row in HStack(spacing:6){ForEach(0..<3){col in key(row*3+col).frame(width:width,height:height)}}.zIndex(activeKey.map{$0/3==row} == true ? 10:0)};key(9).frame(width:width,height:height).zIndex(activeKey==9 ? 10:0)}.frame(maxWidth:.infinity,maxHeight:.infinity)
 }}
 func key(_ index:Int)->some View{FlickKey(index:index,guides:guides.filter{$0.note.key==index},clock:clock,romanMode:romanMode,mediaTime:mediaTime,touchChanged:{down in activeKey=down ? index:nil},input:input)}
}
struct FlickKey:View {
 let index:Int;let guides:[PanelGuideHint];let clock:Double;let romanMode:Bool;let mediaTime:()->Double;let touchChanged:(Bool)->Void;let input:(Int,Int,Double?)->Void
 @AppStorage("fullRoman") private var fullRoman=false
 @AppStorage("panelGuide") private var panelGuide=true
 @AppStorage("flower") private var flower=true
 @State private var downTime:Double?;@State private var direction=0;@State private var touching=false;@State private var releasedAt = -10.0
 var chars:[String]{Array(kanaGroups[index]).map(String.init)}
 var style:KeyboardStyle {KeyboardStyle.selected(roman:romanMode,full:fullRoman)}
 var body:some View{GeometryReader{g in ZStack{
  OriginalSprite(name:String(format:"flickpanel_\(style.family)_\(touching || OriginalVisuals.keyFlash(time:clock,releasedAt:releasedAt) ? "on":"off")_%02d",index))
  if panelGuide {
   ForEach(guides.sorted{$0.scale<$1.scale}){guide in
    OriginalSprite(name:String(format:"guidepanel_\(guide.isNearest ? "on":"off")_%02d",KeyboardStyle.guideSprite(direction:guide.note.direction))).scaleEffect(guide.scale).zIndex(guide.isNearest ? 2:1)
   }
   if guides.contains(where:{$0.isNearest}){OriginalSprite(name:"guidecursor").frame(width:g.size.width*133/127,height:g.size.height*114/108).zIndex(3)}
  }
  if touching && (flower || direction != 0) {flowerView(size:g.size).zIndex(4)}
 }.frame(width:g.size.width,height:g.size.height)}.zIndex(touching ? 10:0).frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle()).accessibilityElement(children:.ignore).accessibilityAddTraits(.isButton).accessibilityLabel(chars[0]+" "+(romanMode ? roman(chars[0]):"")).accessibilityAction{input(index,0,nil)}
 .gesture(DragGesture(minimumDistance:0).onChanged{v in if !touching{downTime=mediaTime();touchChanged(true)};touching=true;let x=v.translation.width,y=v.translation.height;if max(abs(x),abs(y))<14{direction=0}else if abs(x)>abs(y){direction=x<0 ? 1:3}else{direction=y<0 ? 2:4}}.onEnded{_ in input(index,direction,downTime);releasedAt=mediaTime();downTime=nil;touching=false;direction=0;touchChanged(false)})}
 func flowerView(size:CGSize)->some View {ZStack{ForEach(1..<chars.count,id:\.self){d in if !"（）".contains(chars[d]) && (direction==0 || direction==d) {
  ZStack{OriginalSprite(name:String(format:"flickguide_\(direction==d ? "on":"off")_%02d",KeyboardStyle.flowerSprite(direction:d)));flowerCharacter(chars[d]).padding(.horizontal,12).padding(.vertical,8)}.frame(width:size.width*0.68,height:size.height*0.73).offset(x:d==1 ? -size.width*0.69:d==3 ? size.width*0.69:0,y:d==2 ? -size.height*0.72:d==4 ? size.height*0.72:0)
 }}}.allowsHitTesting(false)}
 @ViewBuilder func flowerCharacter(_ char:String)->some View {Text(style == .fullRoman ? roman(char):char).font(AppFont.title2).foregroundStyle(.white)}
}


// Phonetic/letter chart targets drive this keyboard, never the app localization.
struct LetterKeyboard:View {
 let language:NoteInputLanguage;let guides:[PanelGuideHint];let clock:Double;let mediaTime:()->Double;let input:(Int,Int,Double?)->Void
 var body:some View {GeometryReader{g in
  let side=max(1,min((g.size.width-12)/3,(g.size.height-26)/3))
  VStack(spacing:6){Text(language == .chinese ? "PINYIN INITIAL":"WORD INITIAL").font(.system(size:11,weight:.medium,design:.monospaced)).tracking(2).foregroundStyle(teal)
   ForEach(0..<3){row in HStack(spacing:6){ForEach(0..<3){col in let key=row*3+col;LetterFlickKey(index:key,guides:guides.filter{$0.note.key==key},clock:clock,mediaTime:mediaTime,input:input).frame(width:side,height:side)}}}
  }.frame(maxWidth:.infinity,maxHeight:.infinity)
 }}
}
struct LetterFlickKey:View {
 let index:Int;let guides:[PanelGuideHint];let clock:Double;let mediaTime:()->Double;let input:(Int,Int,Double?)->Void
 @State private var touching=false;@State private var direction=0;@State private var downTime:Double?;@State private var releasedAt = -10.0
 var chars:[String]{Array(LetterInputMap.groups[index]).map(String.init)}
 var body:some View {GeometryReader{g in
  let active=touching || OriginalVisuals.keyFlash(time:clock,releasedAt:releasedAt)
  ZStack {
   RoundedRectangle(cornerRadius:10).fill(active ? teal.opacity(0.36):Color(hex:0x132730)).overlay(RoundedRectangle(cornerRadius:10).stroke(teal.opacity(index==0 ? 0.18:0.7),lineWidth:1))
   if !chars.isEmpty{Text(chars[0]).font(.system(size:g.size.height*0.34,weight:.semibold,design:.rounded)).foregroundStyle(.white)
    ForEach(1..<chars.count,id:\.self){d in Text(chars[d]).font(.system(size:g.size.height*0.17,weight:.medium,design:.rounded)).foregroundStyle(touching && direction==d ? .white:teal).position(x:d==1 ? g.size.width*0.15:d==3 ? g.size.width*0.85:g.size.width/2,y:d==2 ? g.size.height*0.15:d==4 ? g.size.height*0.85:g.size.height/2)}
   }else{Image(systemName:"circle.dotted").foregroundStyle(.secondary).accessibilityHidden(true)}
   ForEach(guides){guide in
    RoundedRectangle(cornerRadius:8).stroke(guide.isNearest ? Color.yellow:teal.opacity(0.5),lineWidth:2).scaleEffect(guide.scale)
    if guide.isNearest{Image(systemName:["circle.fill","arrow.left","arrow.up","arrow.right","arrow.down"][guide.note.direction]).foregroundStyle(.yellow).font(.system(size:g.size.height*0.24)).offset(y:g.size.height*0.24)}
   }
  }.frame(width:g.size.width,height:g.size.height)
 }.contentShape(Rectangle()).accessibilityElement(children:.ignore).accessibilityAddTraits(.isButton).accessibilityLabel(chars.isEmpty ? "Unused key":chars.joined(separator:" ")).accessibilityAction{if !chars.isEmpty{input(index,0,nil)}}
 .gesture(DragGesture(minimumDistance:0).onChanged{value in if !touching{downTime=mediaTime()};touching=true;let x=value.translation.width,y=value.translation.height;if max(abs(x),abs(y))<14{direction=0}else if abs(x)>abs(y){direction=x<0 ? 1:3}else{direction=y<0 ? 2:4}}.onEnded{_ in if !chars.isEmpty{input(index,direction,downTime)};touching=false;direction=0;releasedAt=mediaTime();downTime=nil})
 }
}
