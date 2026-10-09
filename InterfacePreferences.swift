import Foundation

enum DeviceOrientationPolicy {
 // Device-specific exception is only for supported rotations, never for layout sizing.
 // iPhone Duo's model identifier comes from Xcode's shipped device profile.
 static func supportsLandscape(isPad:Bool,modelIdentifier:String)->Bool {
  isPad || modelIdentifier == "iPhone19,4"
 }
}

enum Language:String,CaseIterable,Identifiable {
 case en,ja,zh,fr,es,ko
 var id:String {rawValue}
 static func system(preferredLanguages:[String]=Locale.preferredLanguages)->Language {
  // Normalize both Chinese scripts before applying the system preference order.
  let preferences=preferredLanguages.map{$0.lowercased().hasPrefix("zh") ? "zh-Hans":$0}
  let selected=Bundle.preferredLocalizations(from:["en","ja","zh-Hans","fr","es","ko"],forPreferences:preferences).first ?? "en"
  if selected.hasPrefix("zh"){return .zh}
  if selected.hasPrefix("ja"){return .ja}
  return Language(rawValue:selected.split(separator:"-").first.map(String.init) ?? "en") ?? .en
 }
}
enum Handiness:String,CaseIterable,Identifiable {
 case left="LEFT",right="RIGHT"
 var id:String {rawValue}
 var isLeft:Bool {self == .left}
}

enum KeyboardStyle:Int,CaseIterable,Identifiable {
 case original,romanSupport,fullRoman
 var id:Int {rawValue}
 var family:String {["ori","rah","fro"][rawValue]}
 var label:String {["ORIGINAL","ROMAN SUPPORT","FULL ROMAN"][rawValue]}
 static func selected(roman:Bool,full:Bool)->KeyboardStyle {roman ? (full ? .fullRoman:.romanSupport):.original}
 // The atlas orders guide sprites differently from gesture directions.
 static func guideSprite(direction:Int)->Int {[0,3,1,4,2][min(4,max(0,direction))]}
 static func flowerSprite(direction:Int)->Int {[0,2,0,3,1][min(4,max(0,direction))]}
}

// NoteNormal::render reads 78×78 cells from mf_* atlases, not keyboard fgcharacter sprites.
struct NoteGlyph:Equatable {
 let atlas:String;let x:Int;let y:Int;var scale:Double=1
 static func lookup(_ text:String,style:KeyboardStyle,active:Bool=true)->NoteGlyph? {
  let normalized=text.precomposedStringWithCanonicalMapping
  guard normalized.unicodeScalars.count==1,let scalar=normalized.unicodeScalars.first else{return nil}
  let katakana=(0x30A1...0x30F6).contains(scalar.value)
  var code=katakana ? scalar.value-0x60:scalar.value
  var scale=1.0
  // The original table aliases these rare small forms incorrectly; retain their intended glyph.
  if code==0x308E {code=0x308F;scale=0.72}
  if code==0x3095 {code=0x304B;scale=0.72}
  if code==0x3096 {code=0x3051;scale=0.72}
  let state=active ? "telop":"blank"
  let atlas=katakana || code==0x30FC ? "note_katakana_"+state:"note_hiragana_"+style.family+"_"+state
  if code==0x30FC {return NoteGlyph(atlas:atlas,x:858,y:0)}
  let rows=["あいうえおぁぃぅぇぉゔ","かきくけこがぎぐげご","さしすせそざじずぜぞ","たちつてとだぢづでど","なにぬねのばびぶべぼ","はひふへほぱぴぷぺぽ","まみむめもゃゅょわを","らりるれろやゆよっん"]
  for (y,row) in rows.enumerated(){if let x=Array(row.unicodeScalars).firstIndex(where:{$0.value==code}){return NoteGlyph(atlas:atlas,x:x*78,y:y*78,scale:scale)}}
  return nil
 }
}

enum BestRank {
 static let order=["Perfect!","S","A","B","C","D","E"]
 static func strongest(_ ranks:[String])->String? {ranks.compactMap{order.firstIndex(of:$0)}.min().map{order[$0]}}
}
struct MVPlaybackOrder {
 private(set) var songIDs:[String]
 private(set) var cursor=0
 let loop:Bool
 init(songIDs:[String],loop:Bool) {
  var seen=Set<String>();self.songIDs=songIDs.filter{seen.insert($0).inserted};self.loop=loop
 }
 var currentID:String? {songIDs.indices.contains(cursor) ? songIDs[cursor]:nil}
 mutating func advance()->String? {
  guard !songIDs.isEmpty else{return nil}
  if cursor+1<songIDs.count{cursor+=1;return currentID}
  guard loop else{return nil}
  cursor=0;return currentID
 }
 mutating func restart(){cursor=0}
}

struct SubtitleTrack:Codable {
 let songID:String
 let language:String
 let lines:[String:String]
 let sourceURL:String?
 let translator:String?
 let license:String?
 var languageCode:String? {["en","fr","es","ko"].contains(language) ? language:["zh","zh-Hans"].contains(language) ? "zh":nil}
}
struct SubtitleDocument:Codable {
 let formatVersion:Int
 let translations:[SubtitleTrack]
 func validate(songIDs:Set<String>)throws {
  guard formatVersion==1,!translations.isEmpty else{throw SubtitleError.invalid}
  var tracks=Set<String>()
  for track in translations {
   guard songIDs.contains(track.songID),track.songID.range(of:"^[A-Za-z0-9_.-]+$",options:.regularExpression) != nil,let language=track.languageCode,!track.lines.isEmpty,tracks.insert(track.songID+"."+language).inserted else{throw SubtitleError.invalid}
   if let source=track.sourceURL{guard let url=URL(string:source),["http","https"].contains(url.scheme?.lowercased() ?? ""),url.host != nil else{throw SubtitleError.invalid}}
   var normalized:[String:String]=[:]
   for (original,translation) in track.lines {
    let key=SubtitleMap.key(original),value=translation.trimmingCharacters(in:.whitespacesAndNewlines)
    guard !key.isEmpty,original.count<=2000,translation.count<=4000 else{throw SubtitleError.invalid}
    if let existing=normalized[key],existing != value{throw SubtitleError.invalid}
    normalized[key]=value
   }
  }
 }
}
enum SubtitleError:Error {case invalid}
struct SubtitleMap {
 private let lines:[String:String]
 init(_ values:[String:String]){var normalized:[String:String]=[:];for (key,value) in values.sorted(by:{$0.key<$1.key}){normalized[Self.key(key)]=value.trimmingCharacters(in:.whitespacesAndNewlines)};lines=normalized}
 static func key(_ original:String)->String {String(original.precomposedStringWithCompatibilityMapping.unicodeScalars.filter{!CharacterSet.whitespacesAndNewlines.contains($0)})}
 func translation(for original:String,language:Language)->String? {guard language != .ja,!original.isEmpty,let value=lines[Self.key(original)],!value.isEmpty else{return nil};return value}
}


// Dynamic interface copy only; original bitmap labels and song metadata remain assets/content.
enum UIStrings {
 static func text(_ key:String,language:Language)->String {
  let neutral:[String:String] = ["legacyStyle":"CLASSIC","sekaiAStyle":"GRID","sekaiBStyle":"LIST","originalJudgements":"Polygon judgements","originalHelp":"HELP","originalHelpNote":"NegiFlick input rhythm guide.","originalLicenses":"LIBRARIES","originalLicensesNote":"Built-in artwork and audio are independently generated. Imported content remains user-provided.","packHint":"Import a custom chart package or compatible song pack using Files.","packAccessHint":"Only files and folders you select are read. Downloads are stored in Files → NegiFlick → Downloads."]
  let chinese:[String:String] = ["originalJudgements":"多边形判定","originalHelpNote":"NegiFlick 输入法音游帮助。","originalLicensesNote":"内置图像与音频均独立制作；导入内容由用户提供。","packHint":"从“文件”导入自制谱包或兼容曲包。","packAccessHint":"只读取你选择的文件或文件夹。下载保存在“文件”→ NegiFlick → Downloads。"]
  if let value=neutral[key]{return language == .zh ? (chinese[key] ?? value):value}
  guard let value=values[key] else{assertionFailure("Missing UI translation: \(key)");return key}
  return value[Language.allCases.firstIndex(of:language)!]
 }
static let values:[String:[String]] = [
 "downloads":["Downloads", "ダウンロード", "下载列表", "Téléchargements", "Descargas", "다운로드 목록"],
 "addDownload":["Add download", "ダウンロードを追加", "添加下载任务", "Ajouter un téléchargement", "Añadir descarga", "다운로드 추가"],
 "noPackDownloads":["No ZIP or RAR packs found in this release.", "このリリースにZIP／RARパックがありません。", "这个 Release 没有 ZIP 或 RAR 曲包。", "Aucun pack ZIP ou RAR dans cette version.", "Esta versión no contiene paquetes ZIP o RAR.", "이 릴리스에 ZIP 또는 RAR 곡 팩이 없습니다."],
 "downloadListHint":["Add HTTPS ZIP/RAR links or a GitHub release page. Several downloads can run together; completed packs import one at a time. Downloads run while the app is active.", "HTTPSのZIP／RARリンクまたはGitHubリリースページを追加できます。複数を同時にダウンロードし、完了順に1つずつ読み込みます。アプリ使用中にダウンロードします。", "输入 HTTPS ZIP/RAR 直链或 GitHub 发布页。多个任务可同时下载，完成后逐个导入。下载在应用运行期间进行。", "Ajoutez un lien HTTPS ZIP/RAR ou une page de version GitHub. Plusieurs téléchargements peuvent avancer ensemble ; les packs sont importés un par un. Gardez l’app active.", "Añade enlaces HTTPS a ZIP/RAR o una página de versión de GitHub. Las descargas pueden ejecutarse a la vez; los paquetes se importan uno a uno. Mantén la app activa.", "HTTPS ZIP/RAR 링크 또는 GitHub 릴리스 페이지를 추가하세요. 여러 파일을 동시에 다운로드하고 완료된 곡 팩은 하나씩 가져옵니다. 앱 사용 중에 다운로드됩니다."],
 "downloadPaused":["Paused", "一時停止", "已暂停", "En pause", "En pausa", "일시 정지"],
 "downloadQueued":["Waiting to import", "読み込み待ち", "等待导入", "En attente d’importation", "Esperando importación", "가져오기 대기"],
 "downloadImporting":["Importing…", "読み込み中…", "正在导入…", "Importation…", "Importando…", "가져오는 중…"],
 "downloadInstalled":["Imported", "読み込み済み", "已导入", "Importé", "Importado", "가져오기 완료"],
 "downloadFailed":["Failed", "失敗", "失败", "Échec", "Error", "실패"],
 "downloadCancelled":["Cancelled", "キャンセル済み", "已取消", "Annulé", "Cancelado", "취소됨"],
 "pauseDownload":["Pause", "一時停止", "暂停", "Pause", "Pausar", "일시 정지"],
 "resumeDownload":["Resume / retry", "再開／再試行", "继续／重试", "Reprendre / réessayer", "Reanudar / reintentar", "계속 / 다시 시도"],
 "cancelDownload":["Cancel", "キャンセル", "取消", "Annuler", "Cancelar", "취소"],
 "releaseAssets":["Available packs", "ダウンロード可能なパック", "可下载曲包", "Packs disponibles", "Paquetes disponibles", "다운로드 가능한 곡 팩"],
 "removeDownload":["Remove from list", "一覧から削除", "移出列表", "Retirer de la liste", "Quitar de la lista", "목록에서 제거"],
 "emptyDownloads":["No download tasks yet.", "ダウンロードタスクはありません。", "尚未添加下载任务。", "Aucun téléchargement pour le moment.", "Todavía no hay descargas.", "아직 다운로드 작업이 없습니다."],

 "importFolder":["Import InstallData folder", "InstallDataフォルダを読み込む", "导入 InstallData 文件夹", "Importer le dossier InstallData", "Importar carpeta InstallData", "InstallData 폴더 가져오기"],
 "copyingPack":["Copying selected pack files…", "選択したパックをコピー中…", "正在复制所选曲包…", "Copie des fichiers sélectionnés…", "Copiando archivos seleccionados…", "선택한 곡 팩 복사 중…"],
 "downloadPack":["Download and import", "ダウンロードして読み込む", "下载并导入", "Télécharger et importer", "Descargar e importar", "다운로드 및 가져오기"],
 "downloadingPack":["Downloading pack…", "パックをダウンロード中…", "正在下载曲包…", "Téléchargement du pack…", "Descargando paquete…", "곡 팩 다운로드 중…"],
 "httpsPackURL":["Enter an HTTPS pack link or GitHub release page.", "パックのHTTPSリンクまたはGitHubリリースページを入力してください。", "输入曲包 HTTPS 直链或 GitHub 发布页。", "Saisissez un lien HTTPS de pack ou une page de version GitHub.", "Introduce un enlace HTTPS de paquete o una página de versión de GitHub.", "곡 팩 HTTPS 링크 또는 GitHub 릴리스 페이지를 입력하세요."],
 "packAccessHint":["Only files or folders you select are read. Downloads appear in Files → On My iPhone/iPad → NegiFlick → Downloads. Built-in lyric translations appear automatically after song import.", "選択したファイルやフォルダのみ読み込みます。ダウンロードは「ファイル」のこのアプリのDownloadsに保存されます。楽曲の読み込み後、内蔵の歌詞翻訳が自動で表示されます。", "只读取你选择的文件或文件夹。下载保存在“文件”→“我的 iPhone/iPad”→“NegiFlick”→“Downloads”。导入歌曲后，内置歌词译文自动显示。", "Seuls les fichiers ou dossiers sélectionnés sont lus. Les téléchargements se trouvent dans Fichiers → cette app → Downloads. Les traductions intégrées apparaissent après l’importation des morceaux.", "Solo se leen los archivos o carpetas que elijas. Las descargas se guardan en Archivos → esta app → Downloads. Las traducciones incluidas aparecen al importar canciones.", "선택한 파일이나 폴더만 읽습니다. 다운로드는 파일 앱 → 이 앱 → Downloads에 저장됩니다. 곡을 가져오면 내장 가사 번역이 자동으로 표시됩니다."],

 "performanceHUD":["Performance overlay", "パフォーマンス表示", "性能悬浮窗", "Fenêtre de performances", "Panel de rendimiento", "성능 오버레이"],
 "performanceHUDNote":["Drag to move; tap the title to collapse. Shows this app’s CPU and RAM once per second. UI FPS measures display callbacks, not the movie’s frame rate. Sampling stops in the background.", "ドラッグで移動、タイトルをタップで縮小。このアプリのCPUとRAMを毎秒表示します。UI FPSは画面更新コールバックの頻度で、動画のフレームレートではありません。バックグラウンドでは停止します。", "拖动可移动，点击标题可收起。每秒显示本应用 CPU 与 RAM。UI FPS 是屏幕刷新回调频率，不是影片帧率；进入后台停止采样。", "Faites glisser pour déplacer, touchez le titre pour réduire. CPU et RAM de cette app sont actualisés chaque seconde. UI FPS mesure les callbacks d’affichage, pas les images du film. Arrêt en arrière-plan.", "Arrastra para mover; toca el título para contraer. CPU y RAM de esta app se actualizan cada segundo. UI FPS mide callbacks de pantalla, no los fotogramas del vídeo. Se detiene en segundo plano.", "드래그로 이동하고 제목을 탭하면 접힙니다. 앱의 CPU와 RAM을 초당 한 번 표시합니다. UI FPS는 화면 콜백 빈도이며 영상 프레임 수가 아닙니다. 백그라운드에서는 중지합니다."],
 "performanceHUDLegend":["APP · CPU 100% = 1 core\nGPU: Apple Metal HUD", "APP · CPU 100% = 1コア\nGPU: Apple Metal HUD", "本应用 · CPU 100% = 1 个核心\nGPU：Apple Metal HUD", "APP · CPU 100% = 1 cœur\nGPU : Apple Metal HUD", "APP · CPU 100% = 1 núcleo\nGPU: Apple Metal HUD", "앱 · CPU 100% = 코어 1개\nGPU: Apple Metal HUD"],
 "hidePerformanceHUD":["Hide performance overlay", "パフォーマンス表示を隠す", "关闭性能悬浮窗", "Masquer les performances", "Ocultar panel de rendimiento", "성능 오버레이 숨기기"],
 "metalHUDNote":["Apple’s graphics overlay shows GPU time, graphics memory and rendered FPS when a supported Metal surface is present. Restart the app after changing this switch. SwiftUI/video may not expose a Metal surface; GPU percentage is unavailable here and displays —. For detailed GPU utilization, use Xcode Instruments → Metal System Trace on a development device.", "対応Metal描画面ではAppleのHUDがGPU時間、描画メモリ、FPSを表示します。変更後はアプリを再起動してください。SwiftUIや動画でMetal描画面が公開されない場合、この表示は出ません。GPU使用率は取得できず—を表示します。詳細は開発端末でInstrumentsのMetal System Traceを使用してください。", "存在受支持的 Metal 绘制层时，Apple 官方浮层显示 GPU 耗时、图形内存与渲染 FPS。修改后重启应用生效。SwiftUI／视频可能没有可显示的 Metal 绘制层；本悬浮窗无法读取 GPU 百分比，显示 —。详细 GPU 占用请在开发设备上用 Xcode Instruments → Metal System Trace。", "Le HUD Apple affiche le temps GPU, la mémoire graphique et les FPS rendus sur une surface Metal compatible. Redémarrez après modification. SwiftUI/vidéo peut ne pas exposer cette surface ; le pourcentage GPU reste indisponible (—). Pour l’utilisation GPU détaillée, utilisez Instruments → Metal System Trace sur un appareil de développement.", "El HUD de Apple muestra tiempo GPU, memoria gráfica y FPS renderizados con una superficie Metal compatible. Reinicia tras cambiar esta opción. SwiftUI/vídeo puede no exponer esa superficie; el porcentaje GPU no está disponible (—). Usa Instruments → Metal System Trace en un dispositivo de desarrollo para más detalle.", "지원되는 Metal 표면이 있으면 Apple HUD가 GPU 시간, 그래픽 메모리와 렌더링 FPS를 표시합니다. 변경 후 앱을 재시작하세요. SwiftUI/영상은 Metal 표면을 노출하지 않을 수 있어 표시되지 않을 수 있습니다. GPU 백분율은 제공되지 않아 —로 표시합니다. 상세 GPU 사용량은 개발 기기에서 Instruments → Metal System Trace로 확인하세요."],
 "metalHUDHelp":["Apple Metal Performance HUD guide", "Apple Metal Performance HUDガイド", "Apple 官方性能 HUD 说明", "Guide Apple Metal Performance HUD", "Guía de Apple Metal Performance HUD", "Apple Metal Performance HUD 안내"],
 "developer":["Developer", "開発者", "开发者", "Développeur", "Desarrollador", "개발자"],
 "originalJudgements":["Original judgement graphics (hide FAST / LATE)", "原版判定画像（FAST / LATE 非表示）", "原版判定样式（隐藏 FAST / LATE）", "Graphismes de jugement originaux (masquer FAST / LATE)", "Gráficos de juicio originales (ocultar FAST / LATE)", "원작 판정 이미지 (FAST / LATE 숨김)"],
 "autoplayNote":["Automatically judges every note COOL for effect testing. Test scores and records are not saved.", "効果のテスト用にすべてのノーツを自動でCOOL判定します。テストのスコアと記録は保存されません。", "用于特效测试：所有音符自动判定为 COOL。测试得分和记录不会保存。", "Juge automatiquement toutes les notes COOL pour tester les effets. Les scores et records de test ne sont pas enregistrés.", "Juzga automáticamente todas las notas como COOL para probar los efectos. Las puntuaciones y récords de prueba no se guardan.", "효과 테스트를 위해 모든 노트를 자동으로 COOL 판정합니다. 테스트 점수와 기록은 저장하지 않습니다."],
 "testResult":["Test result · not saved", "テスト結果・保存なし", "测试结果 · 不保存", "Résultat de test · non enregistré", "Resultado de prueba · no guardado", "테스트 결과 · 저장 안 함"],
 "originalHelp":["Game guide", "ゲームガイド", "游戏帮助", "Guide du jeu", "Guía del juego", "게임 도움말"],
 "originalHelpNote":["Adapted from the original manual for this version. Original unlocks, replays, Twitter and Game Center services are not implemented. Resource pack import is explained in the final chapter.", "原版の説明書を本版に合わせて更新しています。原版の解放条件・リプレイ・Twitter・Game Centerは未実装です。最後の章でリソースパックの読み込みを説明します。", "本帮助根据原版说明书调整，资源包导入见最后一章。原版解锁条件、重播、Twitter 与 Game Center 服务尚未实现。", "Guide adapté du manuel original pour cette version. Les déblocages, replays, Twitter et Game Center de l'original ne sont pas disponibles. Le dernier chapitre explique l'importation des packs de ressources.", "Guía adaptada del manual original para esta versión. Las condiciones de desbloqueo originales, las repeticiones y los servicios de Twitter y Game Center todavía no están implementados. La importación de paquetes de recursos se explica en el último capítulo.", "이 버전에 맞게 원작 설명서를 수정했습니다. 원작의 해금 조건, 리플레이, Twitter 및 Game Center 서비스는 구현되지 않았습니다. 리소스 팩 가져오기는 마지막 장에서 설명합니다."],
 "originalLicenses":["Original license notices", "原版ライセンス原文", "原版许可原文", "Mentions de licence originales", "Avisos de licencia originales", "원작 라이선스 고지"],
 "originalLicensesNote":["Preserved English notices from the original game. Current remake libraries have their own notices in Vendor.", "原版ゲームの英語ライセンス原文です。本版ライブラリのライセンスはVendorに保存しています。", "以下保留原版游戏的英文许可原文。本版依赖库的许可另存于 Vendor。", "Mentions originales conservées en anglais. Les licences des bibliothèques de cette version se trouvent dans Vendor.", "Se conservan los avisos en inglés del juego original. Las bibliotecas de esta nueva versión tienen sus propios avisos en Vendor.", "원작 게임의 영문 라이선스 고지를 그대로 보존했습니다. 리메이크에 사용된 라이브러리의 라이선스는 Vendor에 따로 있습니다."],
 "packFormat":["Package format & installation guide", "パック形式とインストール手順", "文件包格式与安装教程", "Format des packs et guide d'installation", "Formato de los paquetes y guía de instalación", "파일 구성 및 설치 안내"],
 "extractingPack":["Extracting ZIP / RAR…", "ZIP / RAR を展開中…", "正在解压 ZIP／RAR…", "Extraction du ZIP / RAR…", "Extrayendo ZIP / RAR…", "ZIP / RAR 압축 해제 중…"],
 "verifyingPack":["Checking files…", "ファイルを検証中…", "正在校验文件…", "Vérification des fichiers…", "Comprobando archivos…", "파일 확인 중…"],
 "convertingSong":["Preparing song %d / %d…", "楽曲を変換中 %d / %d…", "正在处理歌曲 %d／%d…", "Préparation du morceau %d / %d…", "Preparando canción %d / %d…", "곡 준비 중 %d / %d…"],
 "registeringPack":["Adding songs to the library…", "楽曲を登録中…", "正在添加到曲库…", "Ajout des morceaux à la bibliothèque…", "Añadiendo canciones a la biblioteca…", "곡 목록에 추가하는 중…"],
 "selected":["Selected", "選択中", "已选择", "Sélectionné", "Seleccionado", "선택됨"],
 "randomSong":["Random song", "ランダム選曲", "随机选曲", "Morceau aléatoire", "Canción aleatoria", "무작위 곡"],
 "resume":["RESUME", "再開", "继续游戏", "REPRENDRE", "CONTINUAR", "계속하기"],
 "retry":["RETRY", "リトライ", "重新开始", "RECOMMENCER", "REINTENTAR", "다시 시작"],
 "musicSelect":["MUSIC SELECT", "楽曲選択", "返回选曲", "CHOIX DU MORCEAU", "SELECCIÓN DE CANCIONES", "곡 선택으로"],
 "inputTiming":["INPUT TIMING", "入力タイミング", "输入时机", "CALAGE DE LA SAISIE", "AJUSTE DE SINCRONIZACIÓN", "입력 타이밍"],
 "resetTiming":["Reset to 0", "0 に戻す", "归零", "Remettre à 0", "Restablecer a 0", "0으로 초기화"],
 "timingPosition":["Original position %+.0f", "原版の設定 %+.0f", "原版档位 %+.0f", "Position d'origine %+.0f", "Posición original %+.0f", "원작 설정값 %+.0f"],
 "timingExplanation":["− judges earlier; + judges later. Saved for this song. Original 30 Hz timing depends on BPM, so some positions share the same millisecond value.", "− は判定を早め、＋ は遅らせます。曲ごとに保存します。原版の 30 Hz 判定は BPM に応じて換算するため、同じミリ秒になる設定があります。", "− 提前判定，+ 延后判定；按歌曲保存。原版以 30 Hz 判定并按 BPM 换算，部分档位会对应相同的毫秒数。", "− avance le jugement ; + le retarde. Réglage enregistré pour ce morceau. Le calage original à 30 Hz dépend du BPM ; certaines positions correspondent donc à la même valeur en millisecondes.", "− adelanta la evaluación; + la retrasa. Se guarda para esta canción. La sincronización original de 30 Hz depende de los BPM, por lo que algunas posiciones tienen el mismo valor en milisegundos.", "−는 판정을 앞당기고 +는 늦춥니다. 곡별로 저장됩니다. 원작의 30 Hz 판정은 BPM에 따라 변환되므로 일부 설정값은 같은 밀리초에 해당합니다."],
 "keyboardSettings":["Keyboard Settings", "キーボード設定", "键盘设置", "Réglages du clavier", "Ajustes del teclado", "키보드 설정"],
 "panelGuideHint":["Show the next note’s tap or flick direction on its key.", "次のノーツのタップ／フリック方向をキーに表示します。", "在对应按键上显示下一音符的点击或滑动方向。", "Affiche la direction du prochain toucher ou glissement sur sa touche.", "Muestra en la tecla el toque o la dirección de deslizamiento de la próxima nota.", "해당 키에 다음 노트의 탭 또는 플릭 방향을 표시합니다."],
 "flowerHint":["Expand the surrounding characters while touching a key.", "キーを押している間、周囲の文字を花びら状に表示します。", "按住按键时展开周围的字符花瓣。", "Déploie les caractères autour de la touche tant que vous la maintenez.", "Despliega los caracteres alrededor de una tecla mientras la mantienes pulsada.", "키를 누르고 있는 동안 주변 문자를 꽃잎처럼 펼칩니다."],
 "songsSelected":["%d SONGS SELECTED [%d / %d]", "%d 曲選択中 [%d / %d]", "已选择 %d 首 [%d / %d]", "%d MORCEAUX SÉLECTIONNÉS [%d / %d]", "%d CANCIONES SELECCIONADAS [%d / %d]", "%d곡 선택됨 [%d / %d]"],
 "handiness":["Handiness", "持ち方", "握持调整", "Prise en main", "Mano de sujeción", "잡는 손 설정"],
 "leftHand":["LEFT HAND", "左手持ち", "左手握持", "MAIN GAUCHE", "MANO IZQUIERDA", "왼손"],
 "rightHand":["RIGHT HAND", "右手持ち", "右手握持", "MAIN DROITE", "MANO DERECHA", "오른손"],
 "handinessNote":["This option behaves differently depending on the device you use.", "この設定の効果は、使用するデバイスによって異なります。", "根据你使用的设备，这个选项会有不同的效果。", "L'effet de ce réglage dépend de l'appareil utilisé.", "El efecto de esta opción depende del dispositivo que utilices.", "사용하는 기기에 따라 이 설정의 효과가 달라집니다."],
 "handinessPortrait":["Portrait iPhone: the right-hand setting places Pause at the lower right and the microphone gauge on the left. The left-hand setting swaps them.", "iPhone の縦向き：右手持ちでは一時停止ボタンが右下、マイクゲージが左側になります。左手持ちでは左右が入れ替わります。", "iPhone 竖屏：默认右手握持时，暂停键在右下角，麦克风计量条在左侧；选择左手握持后，两者换边。", "iPhone en portrait : avec la main droite, Pause se trouve en bas à droite et la jauge du micro à gauche. Avec la main gauche, leurs positions sont inversées.", "iPhone en vertical: la opción de mano derecha coloca Pausa abajo a la derecha y el indicador de micrófono a la izquierda. La opción de mano izquierda intercambia sus posiciones.", "iPhone 세로 화면: 오른손 설정에서는 일시 정지가 오른쪽 아래, 마이크 게이지가 왼쪽에 배치됩니다. 왼손 설정은 두 위치를 바꿉니다."],
 "handinessDuo":["Folded iPhone Duo in landscape: swap the MV and input areas between the left and right sides.", "折りたたんだ iPhone Duo の横向き：MV と入力エリアの左右を切り替えます。", "折叠状态的 iPhone Duo 横屏：切换 MV 和输入区的左右位置。", "iPhone Duo plié en paysage : inverse les positions du MV et de la zone de saisie.", "iPhone Duo plegado en horizontal: intercambia las zonas del MV y de entrada entre los lados izquierdo y derecho.", "접힌 iPhone Duo의 가로 화면: MV와 입력 영역의 좌우 위치를 바꿉니다."],
 "handinessWide":["iPad or fully unfolded iPhone Duo in landscape: the keyboard stays centered in its input area.", "iPad、または完全に開いた iPhone Duo の横向き：キーボードは入力エリアの中央に配置されます。", "iPad 或完全展开的 iPhone Duo 横屏：键盘保持在输入区域中央。", "iPad ou iPhone Duo entièrement déplié en paysage : le clavier reste centré dans sa zone de saisie.", "iPad o iPhone Duo completamente desplegado en horizontal: el teclado permanece centrado en su zona de entrada.", "iPad 또는 완전히 펼친 iPhone Duo의 가로 화면: 키보드는 입력 영역의 중앙에 배치됩니다."],
 "display":["Display", "表示", "显示", "Affichage", "Pantalla", "화면"],
 "audio":["Audio", "音量", "音量", "Audio", "Audio", "음량"],
 "help":["Help", "ヘルプ", "帮助", "Aide", "Ayuda", "도움말"],
 "chooseOptions":["Select an option to change.", "変更する項目を選択してください。", "请选择要调整的设置。", "Choisissez un réglage à modifier.", "Selecciona el ajuste que quieras cambiar.", "변경할 항목을 선택하세요."],
 "systemLanguage":["Language follows your iOS app language setting.", "言語は iOS のアプリ言語設定に従います。", "语言跟随 iOS 的应用语言设置。", "La langue suit le réglage de langue de l'app dans iOS.", "El idioma sigue el ajuste de idioma de la app en iOS.", "언어는 iOS의 앱 언어 설정을 따릅니다."],
 "musicVolume":["MUSIC", "ミュージック", "音乐音量", "MUSIQUE", "MÚSICA", "음악"],
 "sfxVolume":["SFX", "効果音", "音效音量", "EFFETS SONORES", "EFECTOS", "효과음"],
 "failSound":["FAIL SOUND", "失敗時の効果音", "失误提示音", "SON D'ERREUR", "SONIDO DE ERROR", "실수 알림음"],
 "lyrics":["Lyrics", "歌詞", "歌词", "Paroles", "Letra", "가사"],
 "playbackPosition":["Playback position", "再生位置", "播放进度", "Position de lecture", "Posición de reproducción", "재생 위치"],
 "importLyrics":["Import subtitles JSON", "字幕 JSON を読み込む", "导入字幕 JSON", "Importer les sous-titres JSON", "Importar subtítulos JSON", "자막 JSON 가져오기"],
 "lyricsImportHint":["Japanese originals stay visible. Import English, Simplified Chinese, French, Spanish or Korean translations; missing translations are hidden.", "日本語の原文は常に表示します。英語・簡体字中国語・フランス語・スペイン語・韓国語の翻訳を追加できます。未翻訳の行は原文のみ表示します。", "保留日语原文，可导入英文、简体中文、法语、西班牙语或韩语译文；没有译文的句子只显示原文。", "Les paroles japonaises restent affichées. Ajoutez des traductions en anglais, chinois simplifié, français, espagnol ou coréen. Les traductions manquantes sont masquées.", "La letra original japonesa permanece visible. Puedes añadir traducciones al inglés, chino simplificado, francés, español o coreano. Las líneas sin traducción muestran solo el original.", "일본어 원문은 항상 표시됩니다. 영어, 중국어 간체, 프랑스어, 스페인어, 한국어 번역을 추가할 수 있습니다. 번역이 없는 줄에는 원문만 표시됩니다."],
 "lyricsImported":["Subtitle translations imported", "字幕翻訳を追加しました", "字幕译文已导入", "Traductions des sous-titres importées", "Traducciones de subtítulos importadas", "자막 번역을 가져왔습니다"],
 "lyricsInvalid":["Invalid subtitle file or unknown song ID", "字幕形式または楽曲 ID が不正です", "字幕格式不正确，或歌曲 ID 未匹配", "Fichier de sous-titres invalide ou identifiant de morceau inconnu", "Archivo de subtítulos no válido o ID de canción desconocido", "자막 형식이 잘못되었거나 곡 ID를 찾을 수 없습니다"],
 "style":["Style", "スタイル", "界面风格", "Style", "Estilo", "화면 스타일"],
 "library":["Song library", "楽曲一覧", "歌曲库", "Bibliothèque musicale", "Biblioteca de canciones", "곡 목록"], "play":["PLAY", "PLAY", "开始", "JOUER", "JUGAR", "플레이"], "auto":["AUTO", "AUTO", "自动演示", "DÉMO AUTO", "AUTO", "자동 플레이"],
 "mv":["MV playback", "MV 再生", "MV 播放", "Lecture MV", "Reproducción de MV", "MV 재생"], "karaoke":["Karaoke", "カラオケ", "伴奏播放", "Karaoké", "Karaoke", "반주 재생"], "difficulty":["Difficulty", "難易度", "难度", "Difficulté", "Dificultad", "난이도"],
 "keyboard":["Keyboard", "キーボード", "键盘", "Clavier", "Teclado", "키보드"], "kana":["A · Kana", "A · かな", "A · 假名", "A · Kana", "A · Kana", "A · 가나"], "roman":["B · Kana + Romaji", "B · かな＋ローマ字", "B · 假名＋罗马字", "B · Kana + Rōmaji", "B · Kana + Romaji", "B · 가나 + 로마자"],
 "settings":["Settings", "設定", "设置", "Réglages", "Ajustes", "설정"], "timingHints":["FAST / LATE indicators", "FAST / LATE 表示", "显示 FAST / LATE 提示", "Indicateurs FAST / LATE", "Indicadores FAST / LATE", "FAST / LATE 표시"], "stageScore":["Stage score", "ステージスコア", "基础得分", "Score de base", "Puntuación base", "기본 점수"], "comboBonus":["Combo bonus", "コンボボーナス", "连击加分", "Bonus de combo", "Bonificación de combo", "콤보 보너스"], "totalNotes":["Total notes", "総ノーツ数", "总音符数", "Nombre de notes", "Notas totales", "전체 노트 수"], "miniSuccess":["Interlude hits", "間奏成功数", "间奏成功数", "Touches d'interlude réussies", "Aciertos del interludio", "간주 성공 수"], "tutorial":["Tutorial", "遊び方", "教程", "Tutoriel", "Tutorial", "튜토리얼"], "packs":["RESOURCE PACK INPUT", "リソースパック読込", "导入资源包", "IMPORTER UN PACK", "IMPORTAR PAQUETES", "리소스 팩 가져오기"],
 "import":["Import ZIP / RAR", "ZIP / RAR を読み込む", "导入 ZIP / RAR", "Importer un ZIP / RAR", "Importar ZIP / RAR", "ZIP / RAR 가져오기"], "done":["Done", "完了", "完成", "Terminé", "Listo", "완료"], "cancel":["Cancel", "キャンセル", "取消", "Annuler", "Cancelar", "취소"],
 "continue":["Continue", "続ける", "继续", "Continuer", "Continuar", "계속"], "restart":["Restart", "リトライ", "重新开始", "Recommencer", "Reiniciar", "다시 시작"], "back":["Song library", "選曲へ戻る", "返回选曲", "Bibliothèque musicale", "Biblioteca de canciones", "곡 선택으로"],
 "paused":["PAUSED", "PAUSED", "已暂停", "EN PAUSE", "EN PAUSA", "일시 정지"], "result":["Results", "リザルト", "成绩", "Résultats", "Resultados", "결과"], "ended":["Playback finished", "再生終了", "播放结束", "Lecture terminée", "Reproducción terminada", "재생 종료"],
 "next":["Next input", "次の入力", "下一音符", "Prochaine saisie", "Próxima entrada", "다음 입력"], "mini":["INTERLUDE · TAP", "間奏 · タップ", "间奏 · 点击音符", "INTERLUDE · TOUCHER", "INTERLUDIO · TOCAR", "간주 · 탭"], "tap":["TAP", "タップ", "点击", "TOUCHER", "TOCAR", "탭"],
 "clear":["Kana", "清音", "清音", "Kana", "Kana", "청음"], "voiced":["Voiced ゛", "濁音 ゛", "浊音 ゛", "Son voisé ゛", "Sonoros ゛", "탁음 ゛"], "semi":["Semi ゜", "半濁音 ゜", "半浊音 ゜", "Son semi-voisé ゜", "Semisonoros ゜", "반탁음 ゜"], "small":["Small", "小文字", "小字", "Petit caractère", "Pequeños", "작은 글자"],
 "original":["Original chart · reconstructed engine", "原譜面 · 再構築エンジン", "原始谱面 · 重写引擎", "Partition originale · moteur reconstruit", "Partitura original · motor reconstruido", "원작 채보 · 재구현 엔진"],
 "autoHint":["Watch the MV with Japanese lyrics. Karaoke uses accompaniment only.", "日本語歌詞付きで MV を再生します。カラオケは伴奏のみです。", "观看 MV 和日语原文，译文存在时一并显示；伴奏模式只播放伴奏。", "Regardez le MV avec les paroles japonaises et leur traduction, si disponible. Le karaoké utilise uniquement l'accompagnement.", "Mira el MV con la letra japonesa y su traducción cuando esté disponible. Karaoke reproduce solo el acompañamiento instrumental.", "일본어 가사와 함께 MV를 봅니다. 번역이 있으면 함께 표시합니다. 반주 모드에서는 반주만 재생합니다."],
 "playHint":["Follow the indicated key and direction. Grey kana need no input.", "指定キーを矢印方向へフリック。灰色のかなは入力不要です。", "按照提示的按键与方向操作，灰色透明假名不用按。", "Suivez la touche et la direction indiquées. Les kana gris ne demandent aucune saisie.", "Sigue la tecla y la dirección indicadas. Los kana grises no requieren ninguna entrada.", "표시된 키와 방향에 맞춰 조작하세요. 회색 가나는 입력하지 않습니다."],
 "importing":["Installing song pack…", "楽曲パックをインストール中…", "正在安装谱包…", "Installation du pack musical…", "Instalando paquete de canciones…", "곡 팩 설치 중…"], "importSuccess":["Song pack installed", "楽曲パックを追加しました", "谱包已安装", "Pack musical installé", "Paquete de canciones instalado", "곡 팩을 설치했습니다"],
 "importFailed":["Import failed", "読み込みに失敗しました", "导入失败", "Échec de l'importation", "Error de importación", "가져오기 실패"], "mediaFailed":["Cannot play this song", "楽曲を再生できません", "无法播放歌曲", "Impossible de lire ce morceau", "No se puede reproducir esta canción", "이 곡을 재생할 수 없습니다"],
 "packHint":["Download ZIP/RAR packs here, or import a local file or InstallData folder. Finished downloads import automatically; installed songs appear in the library.", "ZIP/RARパックをここでダウンロードするか、ローカルファイルやInstallDataフォルダを読み込めます。ダウンロード完了後に自動で読み込み、楽曲を追加します。", "在这里下载 ZIP/RAR 曲包，或导入本地文件、InstallData 文件夹。下载完成后自动导入，歌曲会出现在曲库。", "Téléchargez des packs ZIP/RAR ici, ou importez un fichier local ou un dossier InstallData. Les téléchargements terminés sont importés automatiquement et les morceaux ajoutés à la bibliothèque.", "Descarga paquetes ZIP/RAR aquí o importa un archivo local o una carpeta InstallData. Las descargas completas se importan automáticamente y las canciones aparecen en la biblioteca.", "여기서 ZIP/RAR 곡 팩을 다운로드하거나 로컬 파일 또는 InstallData 폴더를 가져오세요. 다운로드가 끝나면 자동으로 가져와 곡 목록에 추가합니다."],
 "welcome":["Welcome to NegiFlick", "NegiFlick へようこそ", "欢迎来到 NegiFlick", "Bienvenue dans NegiFlick", "Te damos la bienvenida a NegiFlick", "NegiFlick에 오신 것을 환영합니다"],
 "t1":["Tap & flick", "タップとフリック", "轻点与滑动", "Toucher et glisser", "Tocar y deslizar", "탭과 플릭"],
 "t1body":["The centre kana is a tap. Left / up / right / down select the surrounding kana. Follow the key and arrow shown for each note; voiced kana use their base row.", "中央のかなはタップ。左・上・右・下で周囲のかなを入力します。音符に表示されたキーと矢印に従ってください。濁音は元の行を使います。", "中心假名轻点输入，左、上、右、下滑动选择周围假名。按音符提示的按键和箭头操作，浊音使用对应清音的行。", "Touchez pour saisir le kana central. Glissez à gauche, vers le haut, à droite ou vers le bas pour choisir les kana voisins. Suivez la touche et la flèche de chaque note ; les kana voisés utilisent leur ligne de base.", "Toca para introducir el kana central. Desliza a la izquierda, arriba, derecha o abajo para elegir los kana de alrededor. Sigue la tecla y la flecha de cada nota; los kana sonoros utilizan su fila base.", "가운데 가나는 탭으로 입력합니다. 왼쪽, 위, 오른쪽, 아래로 밀어 주변 가나를 선택합니다. 각 노트의 키와 화살표를 따르세요. 탁음은 해당 청음의 행을 사용합니다."],
 "t2":["Five original difficulties", "原譜面の５つの難易度", "五档原始难度", "Cinq difficultés originales", "Cinco dificultades originales", "원작의 다섯 난이도"],
 "t2body":["Only coloured notes count. Grey kana are lyric guidance. During interludes the keyboard becomes a single large tap button. Tap music notes when they reach the judgement line.", "色付き音符だけを入力します。灰色は歌詞のガイドです。間奏ではキーボードが大きなタップボタンに切り替わります。判定線に音符が来たらタップ。", "只需输入彩色音符，灰色假名用于歌词引导。间奏小游戏把键盘切换成一个大按钮，在音符抵达判定线时点击。", "Seules les notes colorées comptent. Les kana gris guident la lecture des paroles. Pendant les interludes, le clavier devient un grand bouton. Touchez les notes lorsqu'elles atteignent la ligne de jugement.", "Solo cuentan las notas de colores. Los kana grises sirven de guía para la letra. Durante los interludios, el teclado se convierte en un único botón grande. Toca las notas musicales al llegar a la línea de evaluación.", "색이 있는 노트만 입력합니다. 회색 가나는 가사 안내입니다. 간주에서는 키보드가 큰 탭 버튼 하나로 바뀝니다. 음표가 판정선에 도달하면 탭하세요."],
 "t3":["MV, karaoke & song packs", "MV・カラオケ・楽曲パック", "MV、伴奏播放与谱包", "MV, karaoké et packs musicaux", "MV, karaoke y paquetes de canciones", "MV, 반주 및 곡 팩"],
 "t3body":["Open MV from the home menu for video playback. Download ZIP/RAR packs from GitHub and import them into the app. MUSIC, SFX and FAIL SOUND are available in Sound settings.", "ホームの MV から動画を再生できます。GitHub の ZIP/RAR パックを読み込めます。設定では MUSIC、SFX、FAIL SOUND を調整します。", "主菜单的 MV 用于观看音乐视频。下载 GitHub 的 ZIP/RAR 谱包并导入应用。声音设置可调整音乐音量、音效音量和失误提示音。", "Ouvrez MV depuis l'accueil pour regarder les vidéos. Téléchargez des packs ZIP/RAR sur GitHub et importez-les dans l'app. Les réglages Audio permettent d'ajuster la musique, les effets sonores et le son d'erreur.", "Abre MV en el menú principal para ver los vídeos musicales. Descarga paquetes ZIP/RAR de GitHub e impórtalos en la app. En Audio puedes ajustar la música, los efectos y el sonido de error.", "홈 메뉴의 MV에서 음악 영상을 볼 수 있습니다. GitHub에서 ZIP/RAR 곡 팩을 내려받아 앱으로 가져오세요. 음량 설정에서는 음악, 효과음 및 실수 알림음을 조절할 수 있습니다."],
 "start":["Start", "始める", "开始", "Commencer", "Empezar", "시작"], "nextPage":["Next", "次へ", "下一页", "Suivant", "Siguiente", "다음"], "wrong":["EARLY / WRONG", "EARLY / WRONG", "过早 / 输入错误", "TROP TÔT / ERREUR", "ADELANTADO / INCORRECTO", "너무 빠름 / 입력 오류"],
 "preparing":["Preparing media…", "メディアを準備中…", "正在准备媒体…", "Préparation du média…", "Preparando reproducción…", "미디어 준비 중…"],
 "loading":["Loading…", "読み込み中…", "正在载入…", "Chargement…", "Cargando…", "불러오는 중…"],
 "rhythmGame":["RHYTHM GAME", "リズムゲーム", "节奏游戏", "JEU DE RYTHME", "JUEGO DE RITMO", "리듬 게임"],
 "mvAction":["MV", "MV", "音乐视频", "MV", "MV", "MV"],
 "optionsTitle":["OPTIONS", "設定", "设置", "RÉGLAGES", "AJUSTES", "설정"],
 "packInput":["RESOURCE PACK INPUT", "楽曲パック読込", "导入资源包", "IMPORTER UN PACK", "IMPORTAR PAQUETES", "리소스 팩 가져오기"],
 "backAction":["BACK", "戻る", "返回", "RETOUR", "VOLVER", "뒤로"],
 "playMV":["PLAY MV", "MV を再生", "播放 MV", "LIRE LE MV", "REPRODUCIR MV", "MV 재생"],
 "mvSelect":["MV SELECT", "MV 選択", "MV 选曲", "CHOIX DU MV", "SELECCIÓN DE MV", "MV 선택"],
 "songSelect":["MUSIC SELECT", "楽曲選択", "歌曲选择", "CHOIX DU MORCEAU", "SELECCIÓN DE CANCIONES", "곡 선택"],
 "gameMode":["RHYTHM GAME", "リズムゲーム", "节奏游戏", "JEU DE RYTHME", "JUEGO DE RITMO", "리듬 게임"],
 "legacyStyle":["LEGACY", "オリジナル", "经典界面", "CLASSIQUE", "CLÁSICO", "원작 스타일"],
 "sekaiAStyle":["SEKAI-A", "SEKAI-A", "世界风格 A", "SEKAI-A", "SEKAI-A", "SEKAI-A"],
 "sekaiBStyle":["SEKAI-B", "SEKAI-B", "世界风格 B", "SEKAI-B", "SEKAI-B", "SEKAI-B"],
 "songSearch":["Song / artist", "曲名・アーティスト", "查找歌曲名或作者", "Morceau / artiste", "Canción / artista", "곡명 / 아티스트"],
 "highScore":["HIGH SCORE", "ハイスコア", "最高分", "MEILLEUR SCORE", "RÉCORD", "최고 점수"],
 "bpm":["BPM", "BPM", "每分钟节拍", "BPM", "BPM", "BPM"],
 "stars":["Difficulty %d stars", "難易度 %d 星", "难度 %d 星", "Difficulté : %d étoiles", "Dificultad de %d estrellas", "난이도 %d별"],
 "modeChange":["MODE CHANGE", "モード切替", "切换模式", "CHANGER DE MODE", "CAMBIAR MODO", "모드 변경"],
 "normalMode":["NORMAL MODE", "NORMAL MODE", "NORMAL MODE", "NORMAL MODE", "NORMAL MODE", "NORMAL MODE"],
 "difficultyEasy":["EASY", "EASY", "EASY", "EASY", "EASY", "EASY"],
 "difficultyNormal":["NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL", "NORMAL"],
 "difficultyHard":["HARD", "HARD", "HARD", "HARD", "HARD", "HARD"],
 "difficultyExtreme":["EXTREME", "EXTREME", "EXTREME", "EXTREME", "EXTREME", "EXTREME"],
 "difficultyBreak":["BREAK THE LIMIT", "BREAK THE LIMIT", "BREAK THE LIMIT", "BREAK THE LIMIT", "BREAK THE LIMIT", "BREAK THE LIMIT"],
 "coverFlow":["Cover Flow", "ジャケット一覧", "封面选曲", "Choix par pochette", "Selector de portadas", "커버 플로우"],
 "playlist":["PLAYLIST", "プレイリスト", "播放列表", "LISTE DE LECTURE", "LISTA", "재생 목록"],
 "loop":["LOOP", "ループ", "循环播放", "BOUCLE", "REPETIR", "반복 재생"],
 "shuffle":["SHUFFLE", "シャッフル", "随机播放", "ALÉATOIRE", "ALEATORIO", "무작위 재생"],
 "on":["ON", "オン", "开启", "ACTIVÉ", "SÍ", "켬"],
 "off":["OFF", "オフ", "关闭", "DÉSACTIVÉ", "NO", "끔"],
 "noSongs":["No matching songs", "該当する曲がありません", "没有匹配歌曲", "Aucun morceau correspondant", "No hay canciones coincidentes", "일치하는 곡이 없습니다"],
 "level":["Level", "レベル", "等级", "Niveau", "Nivel", "레벨"],
 "keyboardTitle":["KEYBOARD", "キーボード", "键盘", "CLAVIER", "TECLADO", "키보드"],
 "keyboardOriginal":["ORIGINAL", "オリジナル", "原版假名", "ORIGINAL", "ORIGINAL", "원작 가나"],
 "keyboardRomanSupport":["ROMAN SUPPORT", "ローマ字補助", "罗马字辅助", "AIDE RŌMAJI", "APOYO ROMAJI", "로마자 보조"],
 "keyboardFullRoman":["FULL ROMAN", "ローマ字", "全罗马字", "TOUT EN RŌMAJI", "SOLO ROMAJI", "전체 로마자"],
 "panelGuide":["PANEL GUIDE", "パネルガイド", "按键提示", "GUIDE DES TOUCHES", "GUÍA DE TECLAS", "키 안내"],
 "flower":["FLOWER", "フラワー", "字符花瓣", "FLEUR", "PÉTALOS", "꽃잎 표시"],
 "noRecords":["Complete a song to save your first result.", "曲をクリアするとリザルトが保存されます。", "完成一首歌曲后，成绩会自动保存到这里。", "Terminez un morceau pour enregistrer votre premier résultat.", "Completa una canción para guardar tu primer resultado.", "곡을 완료하면 첫 결과가 저장됩니다."],
 "perfect":["Perfect!", "パーフェクト！", "完美通关", "Parfait !", "¡Perfecto!", "퍼펙트!"],
 "score":["SCORE", "スコア", "得分", "SCORE", "PUNTUACIÓN", "점수"],
 "combo":["COMBO", "コンボ", "连击", "COMBO", "COMBO", "콤보"],
 "maxCombo":["MAX COMBO", "最大コンボ", "最高连击", "COMBO MAXIMUM", "COMBO MÁXIMO", "최대 콤보"],
 "totalScore":["TOTAL SCORE", "合計スコア", "总得分", "SCORE TOTAL", "PUNTUACIÓN TOTAL", "총점"],
 "judgementNone":["", "", "", "", "", ""],
 "judgementWorst":["WORST", "WORST", "WORST", "WORST", "WORST", "WORST"],
 "judgementSad":["SAD", "SAD", "SAD", "SAD", "SAD", "SAD"],
 "judgementSafe":["SAFE", "SAFE", "SAFE", "SAFE", "SAFE", "SAFE"],
 "judgementFine":["FINE", "FINE", "FINE", "FINE", "FINE", "FINE"],
 "judgementCool":["COOL", "COOL", "COOL", "COOL", "COOL", "COOL"],
 "fast":["FAST", "FAST", "FAST", "FAST", "FAST", "FAST"],
 "late":["LATE", "LATE", "LATE", "LATE", "LATE", "LATE"],
 "information":["INFORMATION", "インフォメーション", "信息", "INFORMATIONS", "INFORMACIÓN", "정보"],
 "address":["URL", "URL", "网址", "URL", "URL", "URL"],
 "releases":["Releases", "ダウンロード", "下载页面", "Versions à télécharger", "Descargas", "릴리스"],
 "pause":["Pause", "一時停止", "暂停", "Pause", "Pausa", "일시 정지"],
 "microphoneGauge":["Microphone Gauge", "マイクゲージ", "麦克风计量条", "Jauge du micro", "Indicador de micrófono", "마이크 게이지"],
 "subtitleSource":["Subtitle source", "字幕の出典", "字幕来源", "Source des sous-titres", "Fuente de los subtítulos", "자막 출처"],
 "milliseconds":["ms", "ms", "毫秒", "ms", "ms", "ms"],
 "errorPackFolders":["No song-pack folders found.", "楽曲パックのフォルダーがありません。", "未找到有效的谱包文件夹。", "Aucun dossier de pack musical trouvé.", "No se encontraron carpetas de paquetes de canciones.", "곡 팩 폴더를 찾을 수 없습니다."],
 "errorPackMovies":["This pack contains no playable movies.", "再生可能な動画がありません。", "谱包中没有可播放的影片。", "Ce pack ne contient aucune vidéo lisible.", "Este paquete no contiene vídeos reproducibles.", "이 팩에는 재생할 수 있는 영상이 없습니다."],
 "errorVerification":["Song-pack verification failed.", "楽曲パックの検証に失敗しました。", "谱包文件校验失败。", "Échec de la vérification du pack musical.", "La verificación del paquete de canciones ha fallado.", "곡 팩 검증에 실패했습니다."],
 "errorFileMissing":["A required file is missing.", "必要なファイルがありません。", "缺少必要的文件。", "Un fichier requis est manquant.", "Falta un archivo necesario.", "필요한 파일이 없습니다."],
 "errorFileRead":["The file is damaged or cannot be read.", "ファイルが破損しているか、読み込めません。", "文件已损坏或无法读取。", "Le fichier est endommagé ou illisible.", "El archivo está dañado o no se puede leer.", "파일이 손상되었거나 읽을 수 없습니다."],
 "errorAccess":["Cannot access this file.", "このファイルにアクセスできません。", "无法访问该文件。", "Impossible d'accéder à ce fichier.", "No se puede acceder a este archivo.", "이 파일에 접근할 수 없습니다."],
 "errorAudio":["The accompaniment track is unavailable.", "伴奏トラックがありません。", "没有可用的伴奏音轨。", "La piste d'accompagnement est indisponible.", "La pista de acompañamiento no está disponible.", "반주 음원을 사용할 수 없습니다."],
 "errorMedia":["Cannot prepare or play this media.", "動画を準備または再生できません。", "无法准备或播放该媒体。", "Impossible de préparer ou de lire ce média.", "No se puede preparar o reproducir este contenido.", "이 미디어를 준비하거나 재생할 수 없습니다."],
 "errorImport":["Cannot import this file.", "このファイルを読み込めません。", "无法导入该文件。", "Impossible d'importer ce fichier.", "No se puede importar este archivo.", "이 파일을 가져올 수 없습니다."]
]
}

enum TypographyPolicy {
 static let latin="Futura-Medium"
 static func fallback(language:Language)->String {language == .ja ? "HiraginoSans-W3":language == .ko ? "AppleSDGothicNeo-Regular":"PingFangSC-Regular"}
}

// Each row rolls from the units column toward the most significant column.
enum ResultCountup {
 static let columnDelay=0.045
 static let rollDuration=0.24
 static func rowDuration(_ value:Int)->Double {value>0 ? rollDuration+Double(String(value).count-1)*columnDelay:0.12}
 static func totalDuration(_ values:[Int])->Double {values.reduce(0){$0+rowDuration($1)}}
 static func rowElapsed(_ elapsed:Double,slot:Int,values:[Int])->Double {elapsed-values.prefix(max(0,slot)).reduce(0){$0+rowDuration($1)}}
 static func digit(value:Int,columnFromRight:Int,elapsed:Double)->Int {
  guard value>0 else{return 0}
  let digits=Array(String(max(0,value))).reversed().map{Int(String($0))!}
  guard digits.indices.contains(columnFromRight) else{return 0}
  let local=elapsed-Double(columnFromRight)*columnDelay
  guard local>0 else{return 0}
  let target=digits[columnFromRight]
  guard local<rollDuration else{return target}
  return Int(local/rollDuration*Double(20+target))%10
 }
}
