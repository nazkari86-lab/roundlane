#!/usr/bin/env python3
from pathlib import Path
import hashlib,json,os,subprocess,zipfile
kit=Path(__file__).resolve().parents[1]
work=kit/'setup/native-runtime'
macsource=work/'RoundlaneMacSource.zip'
root=kit/'upstream/seb-mac'
names=subprocess.check_output(['git','-C',str(root),'ls-files','-co','--exclude-standard','-z']).decode().split('\0')
with zipfile.ZipFile(macsource,'w',zipfile.ZIP_DEFLATED,compresslevel=6) as z:
 for name in sorted(set(names)):
  p=root/name
  if name and p.is_file(): z.write(p,'upstream/seb-mac/'+name)
 for dirname in ['native-mac','hub','assets']:
  for p in (kit/dirname).rglob('*'):
   rel=p.relative_to(kit)
   if p.is_file() and not set(rel.parts).intersection({'dist','build','.git','__pycache__'}): z.write(p,str(rel))
 for name in ['scripts/build-native-mac.sh','starter.cpp','mac-codeforces-cppsh-demo.seb','native-mac/README.md']:
  if name=='native-mac/README.md':continue
  z.write(kit/name,name)
files={
 'Roundlane Windows.exe':kit/'win-app/dist/Roundlane 3.0 Setup.exe',
 'Roundlane Mac.dmg':kit/'setup/contest-only-check/Roundlane Mac.dmg',
 'Sources/RoundlaneWindowsSource.zip':kit/'win-app/dist/RoundlaneWindowsSource.zip',
 'Sources/RoundlaneMacSource.zip':macsource,
 'Sources/Roundlane Source Changes.zip':kit/'setup/contest-only-check/Roundlane 3.9 Source Changes.zip',
 'LICENSE-SEB-Windows.txt':kit/'win-app/dist/LICENSE-SEB.txt',
 'NOTICE-Windows.txt':kit/'win-app/dist/ROUNDLANE-NOTICE.txt',
 'LICENSE-SEB-Mac.txt':root/'Resources/LICENCE',
 'NOTICE-Mac.txt':root/'Roundlane/NOTICE.txt',
 'Проверка/independent-integrity.md':kit/'docs/independent-integrity-2026-10-11.md',
 'Проверка/windows-signature-results.json':kit/'setup/seb-module-research/windows-signature-results.json',
 'Проверка/standalone-verification.md':kit/'docs/standalone-roundlane-verification-2026-10-10.md',
 'Проверка/windows-installed.json':work/'windows-installed.json',
 'Проверка/windows-session-result.json':work/'windows-session-result.json',
 'Проверка/windows-browser-and-exit.png':work/'windows-browser-and-exit.png',
 'Проверка/windows-desktop-restored.png':work/'windows-desktop-restored.png',
 'Проверка/mac-self-test.json':kit/'setup/contest-only-check/installed-self-test.json',
 'Проверка/mac-webview-check.json':kit/'setup/contest-only-check/installed-webview-check.json',
}
instructions='''Roundlane Mac 3.9 / Windows 3.0

Это самостоятельные приложения со встроенным публичным кодом SEB. Отдельный Safe Exam Browser не нужен.

Windows: запустите Roundlane Windows.exe. Для установки службы нужны права администратора один раз; далее участник запускает Roundlane обычно.
Mac: откройте Roundlane Mac.dmg и перенесите Roundlane в Applications. Сборка ad hoc подписана и не нотариализована.

Организатор вводит точную ссылку /group/.../contest/... и код выхода, сохраняет .roundlane и раздаёт этот файл участникам. Файл содержит хеш кода, а не сам код; короткие коды подбираются перебором. 1234 подходит только для репетиции. Пароли аккаунтов Codeforces выдаются отдельно и в архив не входят.

Участник открывает настройки, нажимает «Начать соревнование» и подтверждает блокировку. Доступ ограничен заданным контестом и компилятором. Несколько окон открываются внутри экзаменационного браузера.
Выход: Windows Ctrl+Q, Mac Cmd+Q, затем код организатора. Сохраните код отдельно до начала. Автозапуск экзамена после перезагрузки не устанавливается.
Windows: в меню Пуск доступна утилита Roundlane Recovery для восстановления после аварии.

Статус: запуск браузера, Codeforces login и штатный выход проверены в Windows ARM64 VM с тестовыми исключениями виртуализации/виртуального дисплея. Поставляемый профиль этих исключений не содержит. Mac прошёл безопасные self-tests без блокировки рабочего компьютера. Подробности в Проверка/standalone-verification.md.

Обновление 11 октября: Windows проверяет Ed25519 подпись списка компонентов и отвергает неизвестные файлы runtime. Проверка перед запуском из формы; защита памяти и доверенная подпись издателя не добавлены. Детали в Проверка/independent-integrity.md. Mac в этом обновлении не менялся.

До олимпиады проведите репетицию на отдельном Mac и реальном Windows x64: вход участника, компиляция, отправка с verdict, запрещённые сайты/программы, штатный выход и восстановление после сбоя. Эквивалентность закрытым модулям защиты официального SEB не заявляется.
'''
new=work/'Roundlane-standalone.zip'
hashes={}
with zipfile.ZipFile(new,'w',zipfile.ZIP_STORED) as z:
 for name,p in files.items():
  hashes[name]=hashlib.file_digest(p.open('rb'),'sha256').hexdigest(); z.write(p,name)
 data=instructions.encode();z.writestr('Перед олимпиадой.txt',data);hashes['Перед олимпиадой.txt']=hashlib.sha256(data).hexdigest()
 z.writestr('SHA256SUMS.txt',''.join(f'{h}  {n}\n' for n,h in hashes.items()))
with zipfile.ZipFile(new) as z:
 assert z.testzip() is None
 for n,h in hashes.items():
  with z.open(n) as f:assert hashlib.file_digest(f,'sha256').hexdigest()==h,n
 for n in z.namelist():assert not any(s in n.lower() for s in ['organizer-private','participant-cards','domain-users','upload-token'])
 for n in ['Sources/RoundlaneWindowsSource.zip','Sources/RoundlaneMacSource.zip']:
  import io
  with zipfile.ZipFile(io.BytesIO(z.read(n))) as nested:
   assert nested.testzip() is None
   assert not any('organizer-private' in p or 'domain-users' in p or 'participant-cards' in p for p in nested.namelist())
old=kit/'dist/Roundlane.zip'
backup=kit/'dist/Roundlane 3.9-2.6 before-standalone.zip'
if old.exists() and not backup.exists():os.link(old,backup)
os.replace(new,old)
public=kit.parent/'Roundlane.zip'
if public.exists():public.unlink()
os.link(old,public)
h=hashlib.file_digest(old.open('rb'),'sha256').hexdigest()
(kit/'dist/Roundlane.zip.sha256').write_text(h+'  Roundlane.zip\n')
public.with_suffix('.zip.sha256').write_text(h+'  Roundlane.zip\n')
report={'archive':str(public),'sha256':h,'bytes':old.stat().st_size,'entries':len(hashes)+1,'crc':'passed','entry_hashes':'passed','credentials_excluded':True}
(work/'standalone-archive-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
