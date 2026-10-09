export const DIFFICULTIES=['EASY','NORMAL','HARD','EXTREME','BTL'];
export const KANA_GROUPS=['あいうえお','かきくけこ','さしすせそ','たちつてと','なにぬねの','はひふへほ','まみむめも','や（ゆ）よ','らりるれろ','わをんー〜'];
const accepted=new Set(Array.from('あいうえおかきくけこさしすせそたちつてとなにぬねのはひふへほまみむめもやゆよらりるれろわをんー〜がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽゔぁぃぅぇぉゃゅょっゎ'));
const mod=Array.from('がぎぐげござじずぜぞだぢづでどばびぶべぼぱぴぷぺぽゔぁぃぅぇぉゃゅょっゎ');
const base=Array.from('かきくけこさしすせそたちつてとはひふへほはひふへほうあいうえおやゆよつわ');
export function hira(t){return t.normalize('NFC').replace(/[ァ-ヶ]/g,c=>String.fromCharCode(c.charCodeAt(0)-0x60));}
export function targetFor(text,language='ja',input=''){
 if(language==='ja'){
  const h=hira(text);if(Array.from(h).length!==1||!accepted.has(h))return null;
  const b=mod.includes(h)?base[mod.indexOf(h)]:h,key=KANA_GROUPS.findIndex(g=>g.includes(b));
  return {symbol:h,key,direction:h==='ー'?2:Array.from(KANA_GROUPS[key]).indexOf(b)};
 }
 let letter;
 if(language==='en'){if(!/^[A-Za-z]+(?:['’][A-Za-z]+)*$/.test(text)||text.length>48)return null;letter=text[0].toUpperCase();if(input&&input.toUpperCase()!==letter)return null;}
 else if(language==='zh'){if(!/^\p{Script=Han}$/u.test(text)||! /^[A-Za-z]$/.test(input))return null;letter=input.toUpperCase();}
 else return null;
 const groups=['','ABC','DEF','GHI','JKL','MNO','PQRS','TUV','WXYZ'];const key=groups.findIndex(g=>g.includes(letter));
 return key<0?null:{symbol:letter,key,direction:groups[key].indexOf(letter)};
}
export function units(text,lang){
 if(lang==='en')return text.match(/[A-Za-z]+(?:['’][A-Za-z]+)*/g)||[];
 if(lang==='zh')return Array.from(text.normalize('NFC')).filter(c=>/^\p{Script=Han}$/u.test(c));
 return Array.from(hira(text)).filter(c=>!/[\s、。！？!?・…「」『』（）(),.]/u.test(c));
}
// Resolve the author's pronunciation before creating any Japanese notes.
// Mixed Japanese lyrics must never become partial kana charts or Latin initials.
export function lyricUnits(row,language){
 const reading=language==='ja'?(row.reading||'').trim():'',a=units(reading||row.text,language);
 if(!a.length)throw Error('入力文字がありません');
 if(language==='ja'&&a.some(c=>!targetFor(c,'ja'))){
  if(reading)throw Error('「読み」は行全体のひらがな・カタカナで入力してください。漢字・英字・数字は使えません。');
  throw Error('漢字・英字などの発音を指定してください。「読み」に歌う行全体をかなで入力します（例：恋の Love → こいのらぶ）。');
 }
 return a;
}
export function keyChoices(key,language='ja'){
 const groups=language==='ja'?KANA_GROUPS:['','ABC','DEF','GHI','JKL','MNO','PQRS','TUV','WXYZ'];
 const choices=Array(5).fill('');
 for(const c of Array.from(groups[key]||'')){
  const t=language==='ja'?targetFor(c,'ja'):targetFor(c,'en');
  if(t?.key===key&&!choices[t.direction])choices[t.direction]=c;
 }
 return choices;
}
export function tick(time){return Math.ceil(time*30);}
export function centerTime(bpm){const b=[80,90,100,110,120,130,140,150,160,170,180,190,200,210,220,230,240];const s=[3,2.9,2.8,2.6,2.4,2.2,2.1,2,1.9,1.8,1.7,1.6,1.5,1.4,1.3,1.2,1.1,1];const i=b.findIndex(x=>bpm<x);return Math.fround(s[i<0?17:i]);}
export function prerollTicks(leadMS,bpm){const lead=leadMS/1000,ct=Math.fround(centerTime(bpm)*30);return Math.floor(lead*30-ct)+Math.trunc(ct);}
export function snap(time,bpm,grid='frame'){if(grid==='off')return Math.max(0,time);const step=grid==='frame'?1/30:60/bpm*4/Number(grid);const v=Math.round(time/step)*step;return Math.max(0,v);}
function stamp(t){const m=t.trim().match(/^(?:(\d+):)?(\d{1,2}):(\d{1,2})(?:[.,](\d+))?$/);if(!m||+m[2]>=60||+m[3]>=60)throw Error('不正なタイムコード: '+t);return +(m[1]||0)*3600+(+m[2])*60+(+m[3])+Number('0.'+(m[4]||'0'));}
export function parseLyrics(text,ext='lrc'){
 text=text.replace(/^\uFEFF/,'').replace(/\r/g,'');let rows=[];
 if(ext==='json'){
  const o=JSON.parse(text),a=Array.isArray(o)?o:o.lyrics;if(!Array.isArray(a))throw Error('lyrics 配列がありません');
  rows=a.map(l=>({time:Number(l.time),text:String(l.text??''),reading:String(l.reading??''),end:l.end==null?null:Number(l.end),tokens:l.tokens||null}));
 }else if(ext==='srt'||text.includes('-->')){
  for(const block of text.trim().split(/\n\s*\n/)){const lines=block.split('\n'),i=lines.findIndex(l=>l.includes('-->'));if(i<0)continue;const [a,b]=lines[i].split('-->');rows.push({time:stamp(a),end:stamp(b.trim().split(/\s+/)[0]),text:lines.slice(i+1).join('\n'),reading:'',tokens:null});}
 }else{
  const off=Number(text.match(/\[offset:([+-]?\d+)\]/i)?.[1]||0)/1000;
  for(const line of text.split('\n')){
   const tags=[...line.matchAll(/\[(\d{1,2}:\d{2}(?:[.,]\d+)?)\]/g)];if(!tags.length)continue;
   const body=line.replace(/\[\d{1,2}:\d{2}(?:[.,]\d+)?\]/g,'').trim();
   let cursor=body.split('<')[0].length;
   const ts=[...body.matchAll(/<(\d{1,2}:\d{2}(?:[.,]\d+)?)>([^<]*)/g)].map(m=>{const offset=cursor+(m[2].length-m[2].trimStart().length);cursor+=m[2].length;return {time:stamp(m[1])+off,text:m[2].trim(),offset};}).filter(x=>x.text);
   for(const tag of tags)rows.push({time:stamp(tag[1])+off,text:body.replace(/<[^>]*>/g,''),reading:'',end:null,tokens:ts.length?ts:null});
  }
 }
 if(!rows.length)throw Error('タイムコード付き歌詞が見つかりません（LRC / SRT / JSON）');
 if(rows.some(l=>!Number.isFinite(l.time)||l.time<0||Array.from(l.text).length>500||l.end!=null&&(!Number.isFinite(l.end)||l.end<=l.time)))throw Error('歌詞の時刻または長さが不正です');
 return rows.sort((a,b)=>a.time-b.time);
}
export function draftFromLyric(row,nextTime,duration,language,difficulties=DIFFICULTIES){
 const end=row.end??Math.min(nextTime??row.time+3,duration-0.5);
 if(end<=row.time)throw Error('行の終了時刻は開始時刻より後にしてください');
 const a=lyricUnits(row,language);
 if(row.tokens?.length&&(language!=='ja'||!row.reading?.trim())){
  // English gameplay always uses word initials, even with character-level lyric timestamps.
  const tokens=language==='en'&&row.tokens.every(t=>Number.isInteger(t.offset))?[...row.text.matchAll(/[A-Za-z]+(?:['’][A-Za-z]+)*/g)].map(m=>({text:m[0],time:row.tokens.find(t=>t.offset>=m.index&&t.offset<m.index+m[0].length)?.time})):row.tokens;
  if(tokens.some(t=>!Number.isFinite(t.time)))throw Error('歌詞の逐字時刻が不足しています');
  return tokens.flatMap((t,i)=>{if(!units(t.text,language).length)return [];const a=lyricUnits(t,language),stop=tokens[i+1]?.time??end;return a.map((kana,j)=>({time:t.time+(stop-t.time)*j/a.length,kana,difficulties:[...difficulties],crimax:false}));});
 }
 return a.map((kana,i)=>({time:row.time+(end-row.time)*i/a.length,kana,difficulties:[...difficulties],crimax:false}));
}
export function timingUnits(text,mode='character'){
 if(mode==='word')return [...text.matchAll(/\S+/gu)].map(m=>({text:m[0],offset:m.index,time:null}));
 const segments=typeof Intl.Segmenter==='function'?[...new Intl.Segmenter('ja',{granularity:'grapheme'}).segment(text)].map(s=>({text:s.segment,offset:s.index})):Array.from(text).reduce((a,c)=>{a.push({text:c,offset:a.reduce((n,x)=>n+x.text.length,0)});return a;},[]);
 return segments.filter(s=>/[\p{L}\p{N}ー〜]/u.test(s.text)).map(s=>({...s,time:null}));
}
export function parsePlainLyrics(text,mode='character'){
 const lines=text.replace(/^\uFEFF/,'').replace(/\r/g,'').split('\n').map(s=>s.trim()).filter(Boolean);
 if(!lines.length||lines.length>10000||lines.some(s=>Array.from(s).length>500))throw Error('歌詞は 1〜10000 行、1 行 500 文字以内にしてください');
 const rows=lines.map(text=>({text,time:null,tokens:timingUnits(text,mode)}));if(mode!=='line'&&rows.some(r=>!r.tokens.length))throw Error('逐字打軸には文字を含む行を使ってください');if(rows.reduce((n,r)=>n+r.tokens.length,0)>20000)throw Error('打軸の文字数は合計 20000 以内にしてください');return rows;
}
export function stampTiming(rows,rowIndex,tokenIndex,time,duration){
 if(!Number.isFinite(time)||time<0||time>=duration)throw Error('歌詞時刻がメディア範囲外です');
 const row=rows[rowIndex];if(!row)throw Error('打軸リストを作ってください。');
 const result=structuredClone(rows),r=result[rowIndex];
 if(tokenIndex===null)r.time=Number(time.toFixed(3));
 else{if(!r.tokens[tokenIndex])throw Error('歌詞の文字がありません');r.tokens[tokenIndex].time=Number(time.toFixed(3));if(tokenIndex===0)r.time=r.tokens[0].time;}
 return result;
}
export function timedLyricRows(rows,mode,duration){
 if(!rows?.length)throw Error('打軸リストを作ってください。');
 let last=-1;
 return rows.map(row=>{
  const tokens=mode==='line'?null:row.tokens,time=mode==='line'?row.time:tokens?.[0]?.time;
  if(time==null||tokens?.some(t=>t.time==null))throw Error('未記録の行・文字があります');
  if(!Number.isFinite(time)||time<0||time>=duration||time<=last)throw Error('歌詞の行時刻は順番に、メディア範囲内で指定してください');
  last=time;let previous=time;
  for(const token of tokens||[]){if(!Number.isFinite(token.time)||token.time<previous||token.time>=duration)throw Error('逐字時刻は順番に、メディア範囲内で指定してください');previous=token.time;}
  return {time,text:row.text,reading:row.reading||'',end:null,tokens:tokens?structuredClone(tokens):null};
 });
}
function lrcStamp(time){const ms=Math.round(time*1000);return `${String(Math.floor(ms/60000)).padStart(2,'0')}:${String(Math.floor(ms/1000)%60).padStart(2,'0')}.${String(ms%1000).padStart(3,'0')}`;}
export function exportLrc(rows,mode,duration){
 return timedLyricRows(rows,mode,duration).map(row=>{
  if(!row.tokens)return `[${lrcStamp(row.time)}]${row.text}`;
  let text='',cursor=0;
  for(const token of row.tokens){text+=row.text.slice(cursor,token.offset)+`<${lrcStamp(token.time)}>`+token.text;cursor=token.offset+token.text.length;}
  return `[${lrcStamp(row.time)}]${text+row.text.slice(cursor)}`;
 }).join('\n')+'\n';
}
export function validate(chart,meta){
 const e=[],need=(c,m)=>{if(!c)e.push(m);};
 need(chart.schemaVersion===1,'schemaVersion は 1');need(['ja','zh','en'].includes(chart.inputLanguage),'入力言語を選択');
 need(Number.isInteger(chart.bpm)&&chart.bpm>=40&&chart.bpm<=400,'BPM は整数 40〜400');
 need(Number.isFinite(chart.duration)&&chart.duration>0&&chart.duration<=600,'動画は 0〜600 秒');
 need(Number.isInteger(chart.leadTimeMS)&&chart.leadTimeMS>=1000&&chart.leadTimeMS<=5000,'先読みは 1000〜5000 ms');
 need(Array.isArray(chart.notes)&&chart.notes.length>0&&chart.notes.length<=10000,'ノーツは 1〜10000 個');
 const occupied=DIFFICULTIES.map(()=>new Map()),offset=prerollTicks(chart.leadTimeMS,chart.bpm);
 for(const [i,n]of (chart.notes||[]).entries()){
  const prefix=`#${i+1}「${n.kana}」`;
  need(Number.isFinite(n.time)&&n.time>0&&n.time<chart.duration-0.5,prefix+' 時刻が動画範囲外');
  need(tick(n.time)-offset>0,prefix+' 先読み時間が不足（先頭に無音/映像の余白が必要）');
  need(!!targetFor(n.kana,chart.inputLanguage,n.input||''),prefix+(chart.inputLanguage==='zh'?' 拼音の頭文字 A〜Z を指定':' 入力文字が不正'));
  need(chart.inputLanguage!=='ja'||n.input==null,prefix+' 日本語 input は不要');
  need(typeof n.crimax==='boolean',prefix+' Crimax が不正');
  need(Array.isArray(n.difficulties)&&n.difficulties.length>0&&new Set(n.difficulties).size===n.difficulties.length&&n.difficulties.every(d=>DIFFICULTIES.includes(d)),prefix+' 難度が不正');
  for(const d of n.difficulties||[]){const ix=DIFFICULTIES.indexOf(d);if(ix<0)continue;const t=tick(n.time);if(occupied[ix].has(t))e.push(`${prefix} / ${d}: #${occupied[ix].get(t)+1} と同じ 30 Hz tick`);else occupied[ix].set(t,i);}
 }
 for(const l of chart.lyrics||[])need(Number.isFinite(l.time)&&l.time>=0&&l.time<chart.duration&&Array.from(l.text).length<=500,'歌詞の時刻/長さが不正');
 if(meta){need(/^[\p{L}\p{N}_.-]{1,64}$/u.test(meta.id),'曲 ID は英数字・-_.（1〜64文字）');need(!!meta.title&&Array.from(meta.title).length<=200,'曲名は 1〜200文字');need(Array.from(meta.artist).length<=200,'作者は 200文字以内');need(meta.levels?.length===5&&meta.levels.every(l=>l===null||Number.isInteger(l)&&l>=1&&l<=99),'レベルは 1〜99');DIFFICULTIES.forEach((d,i)=>{if(meta.levels?.[i]===null&&occupied[i].size)e.push(d+' にノーツがありますがレベルが無効です');if(meta.levels?.[i]!=null&&!occupied[i].size)e.push(d+' のレベルが有効ですがノーツがありません');});}
 return [...new Set(e)];
}
export function authoring(project){return {schemaVersion:1,inputLanguage:project.chart.inputLanguage,bpm:project.chart.bpm,duration:project.chart.duration,leadTimeMS:project.chart.leadTimeMS,notes:project.chart.notes.filter(n=>n.difficulties.length).map(n=>({time:n.time,kana:n.kana,difficulties:DIFFICULTIES.filter(d=>n.difficulties.includes(d)),crimax:!!n.crimax,...(n.input?{input:n.input.toUpperCase()}: {})})),lyrics:project.chart.lyrics.map(l=>({time:l.time,text:l.text}))};}
export function manifest(project,cover=false){return {schemaVersion:1,...project.meta,inputLanguage:project.chart.inputLanguage,bpm:project.chart.bpm,chart:'authoring.json',media:'media.mp4',authoring:true,...(cover?{cover:'cover.png'}:{})};}
export function example(){return {editorVersion:1,meta:{id:'kana-study',title:'Kana Study',artist:'Your name',levels:[1,2,3,4,5]},chart:{schemaVersion:1,inputLanguage:'ja',bpm:120,duration:30,leadTimeMS:1700,notes:Array.from('いろはにほへとちりぬるを').map((kana,i)=>({time:2.1+i*0.5,kana,difficulties:DIFFICULTIES.slice(i%4===0?0:i%2===0?1:2),crimax:i>=10})),lyrics:[{time:2.1,text:'いろはにほへと ちりぬるを',reading:'いろはにほへとちりぬるを',end:8.1}]}};}
export function normalizeProject(data){
 const p=data.editorVersion?data:{editorVersion:1,meta:{id:'my-song',title:'My Song',artist:'',levels:[1,2,3,4,5]},chart:data};
 if(p.editorVersion!==1||!p.meta||!p.chart||!Array.isArray(p.chart.notes)||!Array.isArray(p.chart.lyrics)||p.chart.notes.length>10000||p.chart.lyrics.length>10000)throw Error('NegiFlick エディタのプロジェクトではありません');
 if(!['ja','zh','en'].includes(p.chart.inputLanguage)||!Number.isFinite(p.chart.duration)||p.chart.duration<=0||p.chart.duration>600||!Number.isFinite(p.chart.bpm)||p.chart.bpm<40||p.chart.bpm>400||!Number.isFinite(p.chart.leadTimeMS)||p.chart.leadTimeMS<1000||p.chart.leadTimeMS>5000)throw Error('プロジェクトの設定が不正です');
 if(typeof p.meta.id!=='string'||typeof p.meta.title!=='string'||typeof p.meta.artist!=='string'||!Array.isArray(p.meta.levels)||p.meta.levels.length!==5||p.meta.levels.some(v=>v!==null&&!Number.isFinite(v)))throw Error('曲情報が不正です');
 for(const n of p.chart.notes)if(typeof n.kana!=='string'||n.kana.length>200||!Number.isFinite(n.time)||!Array.isArray(n.difficulties)||n.difficulties.some(d=>!DIFFICULTIES.includes(d))||n.input!=null&&typeof n.input!=='string')throw Error('ノーツの構造が不正です');
 for(const l of p.chart.lyrics){if(typeof l.text!=='string'||l.text.length>2000||!Number.isFinite(l.time)||l.reading!=null&&typeof l.reading!=='string'||l.end!=null&&!Number.isFinite(l.end))throw Error('歌詞の構造が不正です');if(l.tokens!=null&&(!Array.isArray(l.tokens)||l.tokens.length>10000||l.tokens.some(t=>!Number.isFinite(t.time)||typeof t.text!=='string')))throw Error('歌詞トークンが不正です');}
 if(p.lyricTiming){const d=p.lyricTiming;if(!['line','character','word'].includes(d.mode)||!Array.isArray(d.rows)||d.rows.length>10000||d.rows.reduce((n,r)=>n+(r.tokens?.length||0),0)>20000||d.rows.some(r=>typeof r.text!=='string'||r.text.length>2000||r.time!==null&&!Number.isFinite(r.time)||!Array.isArray(r.tokens)||r.tokens.length>500||r.tokens.some((t,i)=>!t.text||i>0&&t.offset<r.tokens[i-1].offset+r.tokens[i-1].text.length||typeof t.text!=='string'||!Number.isInteger(t.offset)||t.offset<0||r.text.slice(t.offset,t.offset+t.text.length)!==t.text||t.time!==null&&!Number.isFinite(t.time))))throw Error('打軸プロジェクトの構造が不正です');}
 return structuredClone(p);
}
