from pathlib import Path
import argparse, math, wave, struct

# Generates original synth sequences without samples or external media.
parser=argparse.ArgumentParser()
parser.add_argument("output", type=Path)
args=parser.parse_args()
args.output.mkdir(parents=True, exist_ok=True)
def wav(path,duration,melody=True):
 rate=24000; seq=[60,64,67,71,69,67,64,62,60,65,69,72,71,67,64,62]
 with wave.open(str(path),'wb') as f:
  f.setparams((1,2,rate,0,'NONE','not compressed'));buf=bytearray()
  for n in range(int(duration*rate)):
   t=n/rate;beat=int(t/.25);phase=t%0.25
   hz=440*2**((seq[beat%len(seq)]-69)/12)
   envelope=min(1,phase/.008)*math.exp(-phase*13)
   # Original sequence, simple synth timbres, no sampled audio.
   tone=math.sin(2*math.pi*hz*t)*.15*envelope if melody else 0
   bass=math.sin(2*math.pi*(130.8128 if int(t/2)%2==0 else 174.6141)*t)*.09*math.exp(-(t%0.5)*8)
   click=math.sin(2*math.pi*900*t)*.045*math.exp(-(t%0.5)*160)
   buf.extend(struct.pack('<h',int(max(-1,min(1,tone+bass+click))*32767)))
  f.writeframes(buf)
wav(args.output / "demo.wav", 30)
wav(args.output / "instrumental.wav", 30, False)
for asset in (Path(__file__).resolve().parent.parent / "GameAssets").glob("*.caf"):
    wav(args.output / (asset.stem + ".wav"), 8 if asset.stem.startswith("BGM") else .10)
print("Generated original demo, instrumental and feedback WAVs. Convert with FFmpeg for the app.")
