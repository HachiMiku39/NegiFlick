import struct,pathlib,json

T={0:('>B',1),1:('>b',1),2:('>H',2),3:('>h',2),4:('>I',4),5:('>i',4),6:('>Q',8),7:('>q',8),8:('>f',4),10:('>I',4),11:('>II',8)}
def parse_utf(b,base):
 rows,strings,data,name,ncol,width,nrow=struct.unpack_from('>IIIIHHI',b,base+8); origin=base+8; sp=origin+strings
 def s(i):
  end=b.find(b'\0',sp+i); return b[sp+i:end].decode('utf-8',errors='replace')
 def value(p,t):
  fmt,size=T[t]; v=struct.unpack_from(fmt,b,p); v=v[0] if len(v)==1 else v
  if t==10:v=s(v)
  if t==11:
   off,length=v;v=b[origin+data+off:origin+data+off+length].rstrip(b"\0").decode("utf-8",errors="replace")
  return v,size
 p=base+32; cols=[]
 for _ in range(ncol):
  flags=b[p]; ni=struct.unpack_from('>I',b,p+1)[0];p+=5; storage=flags&0xf0;t=flags&15; v=None
  if storage==0x30:v,size=value(p,t);p+=size
  cols.append((s(ni),storage,t,v))
 out=[]
 for i in range(nrow):
  p=origin+rows+i*width;r={}
  for key,storage,t,v in cols:
   if storage==0x50:v,size=value(p,t);p+=size
   elif storage==0x10:v=0
   r[key]=v
  out.append(r)
 return s(name),out
