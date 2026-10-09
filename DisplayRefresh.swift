import Foundation

enum DisplayRefreshPolicy {
 static func maximum(screenMaximum:Int)->Int {min(120,max(1,screenMaximum))}
}

#if canImport(UIKit)
import UIKit
import QuartzCore

@MainActor enum DisplayRefresh {
 static func configure(_ link:CADisplayLink,screen:UIScreen?,activePlayback:Bool){
  let maximum=Float(DisplayRefreshPolicy.maximum(screenMaximum:screen?.maximumFramesPerSecond ?? 60))
  // The system can lower cadence for power, thermal or accessibility conditions.
  link.preferredFrameRateRange=CAFrameRateRange(minimum:min(30,maximum),maximum:maximum,preferred:activePlayback ? maximum:0)
 }
 static var activeScreen:UIScreen? {
  UIApplication.shared.connectedScenes.compactMap{$0 as? UIWindowScene}.first{$0.activationState == .foregroundActive && $0.windows.contains(where:{$0.isKeyWindow})}?.screen
 }
}

@MainActor private final class PlaybackDisplayLinkTarget:NSObject {
 weak var owner:PlaybackDisplayClock?
 @objc func frame(_ link:CADisplayLink){owner?.frame()}
}

/// Display-synchronised UI cadence. The callback reads AVPlayer's media clock;
/// display frame counts never become chart judgement ticks or movie frame counts.
@MainActor final class PlaybackDisplayClock {
 private let callback:()->Void
 private let target=PlaybackDisplayLinkTarget()
 private var link:CADisplayLink?
 private var observers:[NSObjectProtocol]=[]
 private var running=false
 init(callback:@escaping ()->Void){
  self.callback=callback;target.owner=self
  for notification in [UIApplication.didBecomeActiveNotification,UIApplication.willResignActiveNotification] {
   observers.append(NotificationCenter.default.addObserver(forName:notification,object:nil,queue:.main){[weak self] _ in
    MainActor.assumeIsolated{
     if notification == UIApplication.willResignActiveNotification{self?.link?.invalidate();self?.link=nil}else{self?.refresh()}
    }
   })
  }
 }
 deinit {link?.invalidate();for observer in observers{NotificationCenter.default.removeObserver(observer)}}
 func setRunning(_ running:Bool){self.running=running;refresh()}
 private func refresh(){
  guard running,UIApplication.shared.applicationState == .active else{link?.invalidate();link=nil;return}
  if let link{DisplayRefresh.configure(link,screen:DisplayRefresh.activeScreen,activePlayback:true);return}
  let link=CADisplayLink(target:target,selector:#selector(PlaybackDisplayLinkTarget.frame(_:)))
  DisplayRefresh.configure(link,screen:DisplayRefresh.activeScreen,activePlayback:true)
  link.add(to:.main,forMode:.common);self.link=link
 }
 fileprivate func frame(){callback()}
}
#endif
