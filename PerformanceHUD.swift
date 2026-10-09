import SwiftUI
import UIKit
import QuartzCore
import Combine

// A separate non-key window stays above navigation, sheets and full-screen gameplay.
// Only the panel accepts touches; the rest of the app remains interactive.
@MainActor final class PerformanceOverlay {
 static let shared=PerformanceOverlay()
 private weak var scene:UIWindowScene?
 private var window:PerformancePassthroughWindow?
 private var controller:PerformanceHUDController?
 private var preferences:AnyCancellable?
 private var lifecycle=[AnyCancellable]()
 private init(){
  preferences=Preferences.shared.objectWillChange.sink{[weak self] _ in
   DispatchQueue.main.async{self?.refresh()}
  }
  for name in [UIApplication.didBecomeActiveNotification,UIApplication.didEnterBackgroundNotification]{
   lifecycle.append(NotificationCenter.default.publisher(for:name).sink{[weak self] _ in self?.refresh()})
  }
 }
 func attach(to scene:UIWindowScene){self.scene=scene;refresh()}
 func refresh(){
  let prefs=Preferences.shared
  AppleMetalHUD.apply(enabled:prefs.effectiveMetalHUD)
  guard prefs.effectivePerformanceHUD,let scene,scene.activationState == .foregroundActive else{
   controller?.stop();window?.isHidden=true;return
  }
  if window?.windowScene !== scene {
   controller?.stop()
   let controller=PerformanceHUDController()
   let window=PerformancePassthroughWindow(windowScene:scene)
   window.rootViewController=controller;window.windowLevel = .normal+1
   window.backgroundColor = .clear;window.panel=controller.panel
   self.window=window;self.controller=controller
  }
  window?.isHidden=false;controller?.start()
 }
}

struct PerformanceOverlayAnchor:UIViewRepresentable {
 func makeUIView(context:Context)->UIView {PerformanceAnchorView()}
 func updateUIView(_ uiView:UIView,context:Context){}
}
private final class PerformanceAnchorView:UIView {
 override func didMoveToWindow(){super.didMoveToWindow();if let scene=window?.windowScene{PerformanceOverlay.shared.attach(to:scene)}}
}
private final class PerformancePassthroughWindow:UIWindow {
 weak var panel:UIView?
 override func hitTest(_ point:CGPoint,with event:UIEvent?)->UIView? {
  guard let panel,panel.bounds.contains(panel.convert(point,from:self)) else{return nil}
  return super.hitTest(point,with:event)
 }
}

enum AppleMetalHUD {
 @MainActor static func apply(enabled:Bool){
  // Apple's documented opt-in applies to subsequent launches. No private GPU counters.
  UserDefaults.standard.set(enabled,forKey:"MetalHUDForceEnabled")
  func visit(_ layer:CALayer){
   if let metal=layer as? CAMetalLayer{metal.developerHUDProperties=enabled ? ["mode":"default"]:[:]}
   for child in layer.sublayers ?? []{visit(child)}
  }
  for scene in UIApplication.shared.connectedScenes.compactMap({$0 as? UIWindowScene}){
   for window in scene.windows{visit(window.layer)}
  }
 }
}

@MainActor private final class PerformanceHUDController:UIViewController {
 let panel=UIView()
 private let header=UIButton(type:.system),close=UIButton(type:.system),rows=UILabel(),footnote=UILabel()
 private var compact=false
 private var relativeCenter:CGPoint?
 private var dragOrigin=CGPoint.zero
 private var displayLink:CADisplayLink?
 private var timer:Timer?
 private var accumulator=PerformanceAccumulator()
 private var cpu:Double?,memory:UInt64?,fps:Double?
 override func loadView(){
  view=UIView();view.backgroundColor = .clear
  panel.backgroundColor=UIColor.black.withAlphaComponent(0.82);panel.layer.cornerRadius=12
  panel.layer.borderWidth=1;panel.layer.borderColor=UIColor.systemTeal.withAlphaComponent(0.7).cgColor
  view.addSubview(panel)
  header.setTitle("PERFORMANCE ▾",for:.normal);header.titleLabel?.font = .monospacedSystemFont(ofSize:11,weight:.semibold)
  header.tintColor = .systemTeal;header.contentHorizontalAlignment = .leading
  header.addTarget(self,action:#selector(toggleCompact),for:.touchUpInside)
  close.setImage(UIImage(systemName:"xmark"),for:.normal);close.tintColor = .white
  close.accessibilityLabel=Preferences.shared.text("hidePerformanceHUD")
  close.addTarget(self,action:#selector(hide),for:.touchUpInside)
  rows.font = .monospacedSystemFont(ofSize:12,weight:.medium);rows.textColor = .white;rows.numberOfLines=0
  footnote.font = .systemFont(ofSize:10);footnote.textColor = .lightGray;footnote.numberOfLines=2
  for v in [header,close,rows,footnote]{panel.addSubview(v)}
  let drag=UIPanGestureRecognizer(target:self,action:#selector(movePanel(_:)));drag.allowedScrollTypesMask = .all;panel.addGestureRecognizer(drag)
  render()
 }
 override func viewDidLayoutSubviews(){
  super.viewDidLayoutSubviews()
  let safe=view.bounds.inset(by:view.safeAreaInsets).insetBy(dx:8,dy:8)
  let width=min(224,max(140,safe.width)),height:CGFloat=compact ? 76:158
  let center=relativeCenter.map{CGPoint(x:safe.minX+$0.x*safe.width,y:safe.minY+$0.y*safe.height)} ?? CGPoint(x:safe.maxX-width/2,y:safe.minY+64+height/2)
  panel.frame=CGRect(x:center.x-width/2,y:center.y-height/2,width:width,height:height)
  clampPanel()
  header.frame=CGRect(x:12,y:0,width:width-56,height:44);close.frame=CGRect(x:width-44,y:0,width:44,height:44)
  rows.frame=CGRect(x:12,y:compact ? 38:44,width:width-24,height:compact ? 32:76)
  footnote.frame=CGRect(x:12,y:122,width:width-24,height:30);footnote.isHidden=compact
 }
 private func clampPanel(){
  let safe=view.bounds.inset(by:view.safeAreaInsets).insetBy(dx:8,dy:8)
  panel.frame.origin.x=min(max(safe.minX,panel.frame.minX),max(safe.minX,safe.maxX-panel.bounds.width))
  panel.frame.origin.y=min(max(safe.minY,panel.frame.minY),max(safe.minY,safe.maxY-panel.bounds.height))
 }
 @objc private func movePanel(_ gesture:UIPanGestureRecognizer){
  if gesture.state == .began{dragOrigin=panel.center}
  let translation=gesture.translation(in:view);panel.center=CGPoint(x:dragOrigin.x+translation.x,y:dragOrigin.y+translation.y);clampPanel()
  let safe=view.bounds.inset(by:view.safeAreaInsets).insetBy(dx:8,dy:8)
  relativeCenter=CGPoint(x:(panel.center.x-safe.minX)/max(1,safe.width),y:(panel.center.y-safe.minY)/max(1,safe.height))
 }
 @objc private func toggleCompact(){compact.toggle();view.setNeedsLayout();render()}
 @objc private func hide(){Preferences.shared.performanceHUD=false}
 func start(){
  guard displayLink == nil else{return}
  loadViewIfNeeded();let sample=ProcessPerformanceSample.read()
  accumulator.reset(time:CACurrentMediaTime(),cpu:sample?.cpuSeconds)
  cpu=nil;fps=nil;memory=sample?.memoryBytes
  let link=CADisplayLink(target:self,selector:#selector(frame(_:)));DisplayRefresh.configure(link,screen:view.window?.windowScene?.screen,activePlayback:false);link.add(to:.main,forMode:.common);displayLink=link
  let timer=Timer(timeInterval:1,target:self,selector:#selector(updateMetrics),userInfo:nil,repeats:true)
  RunLoop.main.add(timer,forMode:.common);self.timer=timer;render()
 }
 func stop(){displayLink?.invalidate();displayLink=nil;timer?.invalidate();timer=nil;accumulator.reset(time:0,cpu:nil)}
 @objc private func frame(_ link:CADisplayLink){accumulator.frame(at:link.timestamp)}
 @objc private func updateMetrics(){
  let sample=ProcessPerformanceSample.read(),values=accumulator.sample(time:CACurrentMediaTime(),cpu:sample?.cpuSeconds)
  cpu=values.cpuPercent;fps=values.uiFPS;memory=sample?.memoryBytes;render()
 }
 private func render(){
  let c=cpu.map{String(format:"%.1f%%",$0)} ?? "—"
  let m=memory.map{String(format:"%.1f MB",Double($0)/1_048_576)} ?? "—"
  let f=fps.map{String(format:"%.0f",$0)} ?? "—"
  header.setTitle(compact ? "PERFORMANCE ▸":"PERFORMANCE ▾",for:.normal)
  rows.text=compact ? "CPU \(c) · \(f) UI FPS\nRAM \(m)":"CPU       \(c)\nRAM       \(m)\nUI FPS    \(f)\nGPU       — · Metal HUD"
  footnote.text=Preferences.shared.text("performanceHUDLegend")
 }
}
