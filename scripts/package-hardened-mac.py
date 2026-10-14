#!/usr/bin/env python3
"""Build/verify the candidate DMG without installing or starting an exam."""
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import subprocess
import zipfile
import argparse

kit = Path(__file__).resolve().parent.parent
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--output', type=Path, default=kit / 'setup/hardened-release')
parser.add_argument('--source', type=Path, default=kit / 'setup/hardened-source/RoundlaneMacSource.zip')
args = parser.parse_args()
candidate = kit / 'setup/Roundlane-hardened-candidate.app'
work = args.output.resolve()
work.mkdir(parents=True, exist_ok=True)
stage = work / 'mac-dmg-stage'
assert stage.resolve().parent == work and not stage.is_symlink()
subprocess.run(['codesign','--verify','--deep','--strict','--all-architectures',str(candidate)],check=True)
run = subprocess.run([str(candidate / 'Contents/MacOS/Roundlane'),'--roundlane-integrity-check'],check=True,capture_output=True,text=True,timeout=30)
assert json.loads(run.stdout)['passed'] is True
source = args.source.resolve()
with zipfile.ZipFile(source) as archive:
    assert archive.testzip() is None
    assert 'upstream/seb-mac/OtherSources/RoundlaneReleaseBinding.swift' in archive.namelist()
seed = (kit / 'organizer-private/runtime-signing.seed').read_bytes()
for path in candidate.rglob('*'):
    if path.is_file():
        data = path.read_bytes()
        assert seed not in data and seed.hex().encode() not in data, path.name
if stage.exists():
    shutil.rmtree(stage)
stage.mkdir()
subprocess.run(['ditto',str(candidate),str(stage / 'Roundlane.app')],check=True)
(stage / 'Applications').symlink_to('/Applications')
shutil.copy2(source,stage / source.name)
shutil.copy2(kit / 'upstream/seb-mac/Resources/LICENCE',stage / 'LICENSE-SEB.txt')
shutil.copy2(kit / 'upstream/seb-mac/Roundlane/NOTICE.txt',stage / 'NOTICE.txt')
(stage / 'Прочитайте.txt').write_text('''Roundlane — проверочная сборка собственной защиты

Приложение содержит встроенный публичный runtime SEB и собственные проверки целостности/памяти. Отдельный SEB не нужен. Автоматический старт экзамена после перезагрузки не устанавливается.

Для установки перенесите Roundlane в Applications после закрытия предыдущей версии. До запуска соревнования сохраните выбранный код выхода отдельно. Cmd+Q, затем код организатора — штатный выход.

Эта сборка подписана ad hoc и собственной подписью выпуска; Developer ID и нотариализации нет. Запуск на чужих Mac и Intel runtime не подтверждены. Полная защищённая Mac сессия и восстановление рабочего стола не проверены. До олимпиады обязательна репетиция на отдельном Mac.

Безопасные проверки подписи, ресурсов, сканера инструкций на отдельном процессе, coordinator и встроенного WebView прошли. Они не доказывают полную защиту памяти или защиту от администратора/ядра ОС. Результаты Windows и оставшиеся проверки указаны в отчёте общего комплекта.

Полные текущие исходники и лицензия приложены. Закрытые ключи и аккаунты участников не включены. Для собственной сборки используйте собственный ключ выпуска и обновите закреплённый открытый ключ; исходный приватный ключ не распространяется.
''')
dmg = work / 'Roundlane Mac Candidate.dmg'
subprocess.run(['hdiutil','create','-ov','-volname','Roundlane Candidate','-srcfolder',str(stage),'-format','UDZO',str(dmg)],check=True)
subprocess.run(['hdiutil','verify',str(dmg)],check=True)
attached = subprocess.run(['hdiutil','attach','-readonly','-nobrowse','-plist',str(dmg)],check=True,capture_output=True)
entities = plistlib.loads(attached.stdout)['system-entities']
mount = next(e['mount-point'] for e in entities if 'mount-point' in e)
try:
    app = Path(mount) / 'Roundlane.app'
    subprocess.run(['codesign','--verify','--deep','--strict','--all-architectures',str(app)],check=True)
    checked = subprocess.run([str(app / 'Contents/MacOS/Roundlane'),'--roundlane-integrity-check'],check=True,capture_output=True,text=True,timeout=30)
    guard = json.loads(checked.stdout)
    assert guard['passed'] is True and guard['exam_started'] is False
    with (Path(mount) / source.name).open('rb') as file:
        mounted_source_hash = hashlib.file_digest(file,'sha256').hexdigest()
    with source.open('rb') as file:
        assert mounted_source_hash == hashlib.file_digest(file,'sha256').hexdigest()
finally:
    subprocess.run(['hdiutil','detach',mount],check=True)
with dmg.open('rb') as file:
    digest = hashlib.file_digest(file,'sha256').hexdigest()
report = dict(candidate_only=True, dmg=str(dmg),sha256=digest,bytes=dmg.stat().st_size,mounted_guard=guard,source_hash_verified=True,license_included=True,private_seed_excluded=True,exam_started=False,installed=False,notarized=False)
(work / 'mac-dmg-verification.json').write_text(json.dumps(report,indent=2)+'\n')
print(json.dumps(report,indent=2))
