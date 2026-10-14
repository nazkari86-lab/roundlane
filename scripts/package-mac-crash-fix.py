from pathlib import Path
import hashlib,json,os,shutil,subprocess,zipfile
kit=Path(__file__).resolve().parents[1]
work=kit/'setup/startup-crash-fix'
changes=work/'Roundlane 3.8 Source Changes.zip'
with zipfile.ZipFile(kit/'setup/startup-fix/Roundlane 3.7 Source Changes.zip') as old, zipfile.ZipFile(changes,'w',zipfile.ZIP_DEFLATED) as out:
    for name in old.namelist():
        if name=='roundlane.patch':
            data=subprocess.check_output(['git','-C',str(kit/'upstream/seb-mac'),'diff','HEAD'])
        else:
            p=kit/name;data=p.read_bytes() if p.is_file() else old.read(name)
        out.writestr(name,data)
    out.write(kit/'docs/startup-crash-fix-2026-10-10.md','docs/startup-crash-fix-2026-10-10.md')
sources=work/'Roundlane Sources.zip'
with zipfile.ZipFile(kit/'setup/startup-fix/Roundlane Sources.zip') as old,zipfile.ZipFile(sources,'w',zipfile.ZIP_DEFLATED) as out:
    for name in old.namelist():
        if name=='Roundlane 3.7 Source Changes.zip':continue
        p=kit/name;out.writestr(name,p.read_bytes() if p.is_file() else old.read(name))
    out.write(changes,changes.name)
    out.write(kit/'docs/startup-crash-fix-2026-10-10.md','docs/startup-crash-fix-2026-10-10.md')
stage=work/'dmg-stage';stage.mkdir(exist_ok=True)
subprocess.run(['ditto',str(kit/'native-mac/dist/Roundlane.app'),str(stage/'Roundlane.app')],check=True)
if not (stage/'Applications').is_symlink():os.symlink('/Applications',stage/'Applications')
shutil.copy2(changes,stage/changes.name)
shutil.copy2(kit/'upstream/seb-mac/Roundlane/NOTICE.txt',stage/'NOTICE.txt')
shutil.copy2(kit/'upstream/seb-mac/Resources/LICENCE',stage/'LICENSE-SEB.txt')
dmg=work/'Roundlane Mac.dmg'
subprocess.run(['hdiutil','create','-volname','Roundlane','-srcfolder',str(stage),'-format','UDZO',str(dmg)],check=True)
subprocess.run(['hdiutil','verify',str(dmg)],check=True)
oldpath=kit/'dist/Roundlane.zip';backup=kit/'dist/Roundlane 3.7-2.5 before-crash-fix.zip'
if not backup.exists():os.link(oldpath,backup)
new=work/'Roundlane.zip';hashes={}
replacements={'Roundlane Mac.dmg':dmg,'Sources/Roundlane Sources.zip':sources,
 'Проверка/startup-crash-fix-2026-10-10.md':kit/'docs/startup-crash-fix-2026-10-10.md',
 'Проверка/runtime-webview-check.json':work/'installed-webview-check.json',
 'Проверка/runtime-settings-check.json':work/'installed-settings-check.json'}
with zipfile.ZipFile(oldpath) as old,zipfile.ZipFile(new,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as out:
    for name in old.namelist():
        if name in replacements or name=='SHA256SUMS.txt':continue
        h=hashlib.sha256()
        with old.open(name) as src,out.open(name,'w') as dst:
            while chunk:=src.read(1024*1024):h.update(chunk);dst.write(chunk)
        hashes[name]=h.hexdigest()
    for name,p in replacements.items():
        out.write(p,name);hashes[name]=hashlib.sha256(p.read_bytes()).hexdigest()
    out.writestr('SHA256SUMS.txt',''.join(f'{digest}  {name}\n' for name,digest in sorted(hashes.items())))
with zipfile.ZipFile(new) as z:
    assert z.testzip() is None
    for name,digest in hashes.items():
        h=hashlib.sha256()
        with z.open(name) as f:
            while chunk:=f.read(1024*1024):h.update(chunk)
        assert h.hexdigest()==digest,name
with zipfile.ZipFile(backup) as z:assert hashlib.sha256(z.read('Roundlane Windows.exe')).hexdigest()==hashes['Roundlane Windows.exe']
oldpath.unlink();os.link(new,oldpath)
public=kit.parent/'Roundlane.zip';public.unlink();os.link(new,public)
report={'zip_crc':'passed','entry_hashes':'passed','windows_unchanged':True,'sha256':hashlib.sha256(new.read_bytes()).hexdigest()}
(work/'archive-verification.json').write_text(json.dumps(report,indent=2))
print(json.dumps(report))
