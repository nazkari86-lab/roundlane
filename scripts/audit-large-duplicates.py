import os,hashlib,json,stat
from pathlib import Path
from collections import defaultdict
home=Path('/Users/dulatnurlanuly')
roots=[home/p for p in ['.ollama/models','.cache/huggingface','models','Ornith-1.0-9B','ornith-4bit-mlx','ornith-ft','medical-models','Qwen3-TTS-12Hz-1.7B-CustomVoice','MiniCPM-V-4.6','minicpm-ft','.locai/checkpoints','data','Downloads/flybrain','Downloads/shared-data']]
files=[home/'ornith-q4km.gguf']
for root in roots:
    if root.is_dir():
        for d,dirs,names in os.walk(root,followlinks=False):
            dirs[:]=[n for n in dirs if n not in ['.git','node_modules']]
            files.extend(Path(d)/n for n in names)
sizes=defaultdict(list); seen=set()
for p in files:
    try:
        s=p.lstat()
        if not stat.S_ISREG(s.st_mode) or s.st_size<32*1024**2: continue
        key=(s.st_dev,s.st_ino)
        if key in seen: continue
        seen.add(key); sizes[s.st_size].append(p)
    except OSError: pass
partial=defaultdict(list)
for size,paths in sizes.items():
    if len(paths)<2: continue
    for p in paths:
        with p.open('rb') as f:
            h=hashlib.sha256(f.read(65536));f.seek(-65536,2);h.update(f.read(65536))
        partial[(size,h.digest())].append(p)
result=[]
for (size,_),paths in partial.items():
    if len(paths)<2: continue
    hashes=defaultdict(list)
    for p in paths:
        h=hashlib.sha256()
        with p.open('rb') as f:
            while data:=f.read(8*1024**2):h.update(data)
        hashes[h.hexdigest()].append(str(p))
    for digest,group in hashes.items():
        if len(group)>1:
            result.append({'size':size,'sha256':digest,'paths':group})
            print('Identical group',size,len(group),flush=True)
out=home/'Downloads/seb-contest-kit/docs/large-duplicates-2026-10-09.json'
out.write_text(json.dumps(result,indent=2))
print(json.dumps({'groups':len(result),'logical_duplicate_bytes':sum(x['size']*(len(x['paths'])-1) for x in result),'report':str(out)}),flush=True)
