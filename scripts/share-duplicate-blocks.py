import ctypes,os,json,hashlib,subprocess,shutil,tempfile,stat
from pathlib import Path
root=Path('/Users/dulatnurlanuly/Downloads/seb-contest-kit')
lib=ctypes.CDLL('/usr/lib/libSystem.B.dylib',use_errno=True)
lib.clonefile.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_int];lib.clonefile.restype=ctypes.c_int
lib.copyfile.argtypes=[ctypes.c_char_p,ctypes.c_char_p,ctypes.c_void_p,ctypes.c_uint32];lib.copyfile.restype=ctypes.c_int

def clone(a,b):
    if lib.clonefile(os.fsencode(a),os.fsencode(b),0):
        code=ctypes.get_errno();raise OSError(code,os.strerror(code))
def digest(p):
    h=hashlib.sha256()
    with p.open('rb') as f:
        while data:=f.read(8*1024**2):h.update(data)
    return h.hexdigest()
with tempfile.TemporaryDirectory(prefix='Roundlane-clone-check-') as d:
    a=Path(d)/'a';b=Path(d)/'b';a.write_bytes(b'original');clone(a,b);b.write_bytes(b'changed')
    assert a.read_bytes()==b'original'
opened={line[1:] for line in subprocess.run(['lsof','-n','-F','n'],capture_output=True,text=True).stdout.splitlines() if line.startswith('n')}
before=shutil.disk_usage(root).free;changes=[]
for group in json.loads((root/'docs/large-duplicates-2026-10-09.json').read_text()):
    source=Path(group['paths'][0])
    if digest(source)!=group['sha256']: raise RuntimeError('Source changed')
    for item in group['paths'][1:]:
        target=Path(item);s=target.lstat()
        if item in opened or not stat.S_ISREG(s.st_mode) or s.st_nlink!=1 or s.st_flags:
            changes.append({'path':item,'action':'skipped in-use or special metadata'});continue
        if digest(target)!=group['sha256']: raise RuntimeError('Target changed')
        snapshot=(s.st_ino,s.st_size,s.st_mtime_ns)
        temp=target.with_name(target.name+'.roundlane-apfs-clone')
        try:
            clone(source,temp)
            subprocess.run(['/usr/bin/xattr','-c',str(temp)],check=True)
            if lib.copyfile(os.fsencode(target),os.fsencode(temp),None,7):
                code=ctypes.get_errno();raise OSError(code,os.strerror(code))
            if digest(temp)!=group['sha256']:raise RuntimeError('Clone hash mismatch')
            now=target.stat()
            if (now.st_ino,now.st_size,now.st_mtime_ns)!=snapshot:raise RuntimeError('Target changed during clone')
            with temp.open('rb') as f:os.fsync(f.fileno())
            os.replace(temp,target)
            changes.append({'path':item,'source':str(source),'sha256':group['sha256'],'action':'APFS clone; content preserved'})
            print('Cloned',item,flush=True)
        finally:
            if temp.exists():temp.unlink()
after=shutil.disk_usage(root).free
report={'free_bytes_before':before,'free_bytes_after':after,'physical_bytes_freed':after-before,'changes':changes}
(root/'docs/apfs-dedup-2026-10-09.json').write_text(json.dumps(report,indent=2))
print(json.dumps({'physical_bytes_freed':after-before,'free_bytes_after':after}),flush=True)
