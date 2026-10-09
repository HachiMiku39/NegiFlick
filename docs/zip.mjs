// Uncompressed ZIP, UTF-8 names, sliced CRC calculation; no uploads or dependencies.
const table=Array.from({length:256},(_,n)=>{for(let i=0;i<8;i++)n=(n&1)?0xedb88320^(n>>>1):n>>>1;return n>>>0;});
export async function crc32(blob){let crc=0xffffffff;for(let at=0;at<blob.size;at+=1048576){for(const b of new Uint8Array(await blob.slice(at,at+1048576).arrayBuffer()))crc=table[(crc^b)&255]^(crc>>>8);}return (crc^0xffffffff)>>>0;}
function block(size){const b=new Uint8Array(size);return {b,v:new DataView(b.buffer)};}
export async function zipStore(files,progress=()=>{}){
 const parts=[],central=[];let offset=0,cdSize=0;
 for(const [i,{name,blob}]of files.entries()){
  if(!/^[A-Za-z0-9_.-]+$/.test(name)||blob.size>=0xffffffff)throw Error('ZIP ファイル名またはサイズが不正');
  progress(i,files.length);const crc=await crc32(blob),n=new TextEncoder().encode(name),h=block(30+n.length);
  h.v.setUint32(0,0x04034b50,true);h.v.setUint16(4,20,true);h.v.setUint16(6,0x800,true);h.v.setUint32(14,crc,true);h.v.setUint32(18,blob.size,true);h.v.setUint32(22,blob.size,true);h.v.setUint16(26,n.length,true);h.b.set(n,30);
  parts.push(h.b,blob);const c=block(46+n.length);c.v.setUint32(0,0x02014b50,true);c.v.setUint16(4,20,true);c.v.setUint16(6,20,true);c.v.setUint16(8,0x800,true);c.v.setUint32(16,crc,true);c.v.setUint32(20,blob.size,true);c.v.setUint32(24,blob.size,true);c.v.setUint16(28,n.length,true);c.v.setUint32(42,offset,true);c.b.set(n,46);central.push(c.b);cdSize+=c.b.length;offset+=h.b.length+blob.size;
  if(offset+cdSize>=0xffffffff)throw Error('ZIP は 4 GB 未満にしてください');
 }
 const end=block(22);end.v.setUint32(0,0x06054b50,true);end.v.setUint16(8,files.length,true);end.v.setUint16(10,files.length,true);end.v.setUint32(12,cdSize,true);end.v.setUint32(16,offset,true);
 progress(files.length,files.length);return new Blob([...parts,...central,end.b],{type:'application/zip'});
}
