#!/usr/bin/env python3
"""Apply the Roundlane identity to the public Windows SEB source, idempotently."""
from pathlib import Path
import re
import shutil
import subprocess

kit = Path(__file__).resolve().parents[1]
src = kit / 'upstream/seb-win-refactoring'

def edit(relative, transform):
    path = src / relative
    old = path.read_text(encoding='utf-8-sig')
    new = transform(old)
    if new != old:
        path.write_text(new, encoding='utf-8-sig')

for project, name in [('Runtime', 'Roundlane.Runtime'), ('Client', 'Roundlane.Client'),
                      ('Service', 'Roundlane.Service'), ('ResetUtility', 'Roundlane.Recovery')]:
    edit(f'SafeExamBrowser.{project}/SafeExamBrowser.{project}.csproj',
         lambda text, name=name: re.sub(r'<AssemblyName>[^<]+</AssemblyName>', f'<AssemblyName>{name}</AssemblyName>', text))
    edit(f'SafeExamBrowser.{project}/Properties/AssemblyInfo.cs',
         lambda text, name=name: re.sub(r'(Assembly(?:FileVersion|InformationalVersion)\(")[^"]+("\))', lambda m:m[1]+'3.0.0.0'+m[2],
             re.sub(r'(Assembly(?:Title|Product)\(")[^"]+("\))', lambda m: m[1] + name + m[2], text))
             .replace('AssemblyCompany("ETH Zürich")','AssemblyCompany("Roundlane")')
             .replace('AssemblyDescription("Safe Exam Browser")','AssemblyDescription("Roundlane with public SEB components")'))
    ico = src / f'SafeExamBrowser.{project}/SafeExamBrowser.ico'
    if ico.exists():
        shutil.copy2(kit / 'win-app/app.ico', ico)

edit('SafeExamBrowser.Runtime/Properties/AssemblyInfo.cs', lambda t: t.replace('Roundlane.Runtime', 'Roundlane'))
edit('SafeExamBrowser.Configuration/ConfigurationData/DataValues.cs',
     lambda t: t.replace('nameof(SafeExamBrowser)', '"Roundlane"')
                .replace('$"{"Roundlane"}.Client.exe"', '"Roundlane.Client.exe"')
                .replace('SebClientSettings.seb', 'RoundlaneClientSettings.seb'))
edit('SafeExamBrowser.Configuration.Contracts/AppConfig.cs',
     lambda t: t.replace('net.pipe://localhost/safeexambrowser', 'net.pipe://localhost/roundlane')
                .replace('safe_exam_browser_', 'roundlane_'))
for path in ['SafeExamBrowser.Service/CompositionRoot.cs', 'SafeExamBrowser.ResetUtility/CompositionRoot.cs',
             'SafeExamBrowser.ResetUtility/Procedure/Restore.cs']:
    edit(path, lambda t: t.replace('nameof(SafeExamBrowser)', '"Roundlane"'))
for path in ['SafeExamBrowser.Service/Installer.cs', 'SafeExamBrowser.Service/Service.cs']:
    edit(path, lambda t: t.replace('nameof(SafeExamBrowser)', '"Roundlane"')
                           .replace('Safe Exam Browser Service', 'Roundlane Exam Service'))

def monitor(text):
    text = text.replace('using System.Linq;', 'using System.Linq;\nusing System.IO;\nusing System.Reflection;') if 'using System.IO;' not in text else text
    start = text.index('\t\tprivate bool BelongsToSafeExamBrowser(IProcess process)')
    end = text.index('\n\t\tprivate void Close(', start)
    # Pin executables to this installation, rather than accepting a renamed foreign process.
    body = '''\t\tprivate bool BelongsToSafeExamBrowser(IProcess process)
\t\t{
\t\t\tvar root = Path.GetDirectoryName(Assembly.GetEntryAssembly().Location);
\t\t\tvar isClient = process.Name == "Roundlane.Client.exe" && process.OriginalName == "Roundlane.Client.exe";
\t\t\tvar isRuntime = process.Name == "Roundlane.Runtime.exe" && process.OriginalName == "Roundlane.Runtime.exe";
\t\t\tvar sameInstallation = string.Equals(Path.GetDirectoryName(process.Path), root, StringComparison.OrdinalIgnoreCase);
\t\t\tvar ownCertificate = Assembly.GetEntryAssembly().Modules.First().GetSignerCertificate()?.GetCertHashString();
\t\t\tvar samePublisher = string.Equals(process.Signature, ownCertificate, StringComparison.OrdinalIgnoreCase);
\t\t\treturn (isClient || isRuntime) && sameInstallation && samePublisher;
\t\t}
'''
    return text[:start] + body + text[end:]
edit('SafeExamBrowser.Monitoring/Applications/ApplicationMonitor.cs', monitor)
edit('SafeExamBrowser.Runtime/App.cs', lambda t: t.replace('one instance of SEB', 'one instance of Roundlane'))
edit('SafeExamBrowser.UserInterface.Desktop/Windows/RuntimeWindow.xaml', lambda t: t.replace('Title="Safe Exam Browser"', 'Title="Roundlane"'))
edit('SafeExamBrowser.UserInterface.Desktop/Windows/LockScreen.xaml', lambda t: t.replace('SEB LOCKED', 'ROUNDLANE LOCKED'))
for folder in ['SafeExamBrowser.UserInterface.Desktop', 'SafeExamBrowser.UserInterface.Mobile', 'SafeExamBrowser.UserInterface.Shared']:
    for ico in (src / folder).rglob('SafeExamBrowser.ico'):
        shutil.copy2(kit / 'win-app/app.ico', ico)
    for splash in (src / folder).rglob('SplashScreen.png'):
        subprocess.run(['magick','-background','none',str(kit / 'assets/roundlane.svg'),'-resize','140x140',
                        '-background','white','-gravity','center','-extent','190x300','-gravity','west','-extent','550x300',str(splash)],check=True)
for resource in (src / 'SafeExamBrowser.I18n/Data').glob('*.xml'):
    edit(str(resource.relative_to(src)),lambda t: '\n'.join(line.rstrip() for line in re.sub(r'\bSEB\b','Roundlane',t.replace('Safe Exam Browser','Roundlane')).splitlines()) + '\n')

notice = '''Roundlane Windows is a modified build of the public Safe Exam Browser source.
Upstream: https://github.com/SafeExamBrowser/seb-win-refactoring
Revision: 167f82f8c3ec6773ec9be6c5af7fb492b5b2ed50
Covered source files remain under MPL-2.0; original copyright notices are preserved.
Changes: product identity, isolated IPC/service/cache, bundled runtime selection.
The proprietary SEB integrity DLL is not included and official Browser Exam Key
compatibility and official SEB integrity protection are not claimed.
Build: scripts/build-native-windows.ps1; source: included source archive.
'''
(src / 'ROUNDLANE-NOTICE.txt').write_text(notice)
print('Roundlane Windows source prepared')
