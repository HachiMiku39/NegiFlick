import Foundation

enum InputLanguageError:Error,LocalizedError {case invalid(String);var errorDescription:String?{if case let .invalid(message)=self{return message};return nil}}

// Song input language is independent of app localization and lyric translations.
enum NoteInputLanguage:String,Codable,CaseIterable {
 case japanese="ja",chinese="zh",english="en"
 static func parse(_ tag:String)throws->Self {
  let prefix=tag.lowercased().replacingOccurrences(of:"_",with:"-").split(separator:"-").first.map(String.init) ?? ""
  guard let language=Self(rawValue:prefix) else{throw InputLanguageError.invalid("Unsupported input language: \(tag)")}
  return language
 }
}
enum InputLanguageResolver {
 static func resolve(declared:String?,targets:[String],legacy:Bool=false)throws->NoteInputLanguage {
  if let declared{return try NoteInputLanguage.parse(declared)}
  if legacy{return .japanese}
  let scalars=targets.joined().unicodeScalars
  let kana=scalars.contains{(0x3040...0x30FF).contains($0.value)}
  let han=scalars.contains{(0x3400...0x9FFF).contains($0.value) || (0x20000...0x3134F).contains($0.value)}
  let latin=scalars.contains{(65...90).contains($0.value) || (97...122).contains($0.value)}
  guard !(latin && (kana || han)) else{throw InputLanguageError.invalid("Mixed-script targets require an explicit input language")}
  if kana{return .japanese}
  if han{throw InputLanguageError.invalid("Han characters require language ja or zh; character shape alone is ambiguous")}
  if latin{return .english}
  throw InputLanguageError.invalid("Declare an input language for this chart")
 }
}

// Standard phone-letter groups; tap, left, up, right, down keep existing gesture IDs.
enum LetterInputMap {
 static let groups=["", "ABC", "DEF", "GHI", "JKL", "MNO", "PQRS", "TUV", "WXYZ"]
 static func position(_ input:String)->(key:Int,direction:Int)? {
  guard input.count==1 else{return nil}
  let letter=input.uppercased()
  for (key,group) in groups.enumerated(){if let direction=Array(group).firstIndex(where:{String($0)==letter}){return (key,direction)}}
  return nil
 }
}

enum InitialInputTarget {
 static func isHan(_ text:String)->Bool {
  text.count == 1 && text.unicodeScalars.contains{(0x3400...0x9FFF).contains($0.value) || (0x20000...0x3134F).contains($0.value)}
 }
 static func englishInitial(_ word:String)->String? {
  // One word per hit; apostrophes within contractions do not create another hit.
  guard word.count<=48,word.range(of:"^[A-Za-z]+(?:['’][A-Za-z]+)*$",options:.regularExpression) != nil,let first=word.first else{return nil}
  return String(first).uppercased()
 }
 static func resolve(_ text:String,input:String?,language:NoteInputLanguage)throws->String {
  switch language {
  case .english:
   guard let initial=englishInitial(text),input == nil || input?.uppercased()==initial else{throw InputLanguageError.invalid("English notes require one word and its first letter")}
   return initial
  case .chinese:
   guard isHan(text) else{throw InputLanguageError.invalid("Chinese notes require one Han character per hit")}
   // Authors may override a polyphonic reading with its single pinyin initial.
   let latin=text.applyingTransform(.toLatin,reverse:false)?.applyingTransform(.stripDiacritics,reverse:false)
   let initial=input?.uppercased() ?? latin?.first.map{String($0).uppercased()} ?? ""
   guard LetterInputMap.position(initial) != nil else{throw InputLanguageError.invalid("Specify a pinyin initial for this character")}
   return initial
  case .japanese:throw InputLanguageError.invalid("Initial input is only used for Chinese and English")
  }
 }
}
