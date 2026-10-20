"""Render actual SwiftUI on iOS Simulator; this does not test physical pairing."""
import json
import platform
from pathlib import Path
import subprocess
import time

def run(*args):
    return subprocess.check_output(args, text=True).strip()

output = Path('build/UI')
output.mkdir(parents=True,exist_ok=True)
core = Path('build/UICore').resolve()
core.mkdir(exist_ok=True)
arch = platform.machine()
sdk = run('xcrun','--sdk','iphonesimulator','--show-sdk-path')
subprocess.run(['xcrun','clang','-target',f'{arch}-apple-ios18.0-simulator','-isysroot',sdk,'-c','scripts/PreviewCore.c','-o',str(core/'stub.o')],check=True)
subprocess.run(['xcrun','ar','rcs',str(core/'libsiderelay_core.a'),str(core/'stub.o')],check=True)
subprocess.run(['xcodebuild','-project','SideRelay.xcodeproj','-scheme','SideRelay','-configuration','Debug','-sdk','iphonesimulator','-destination','generic/platform=iOS Simulator',f'ARCHS={arch}','-derivedDataPath','build/Preview','CODE_SIGNING_ALLOWED=NO',f'LIBRARY_SEARCH_PATHS={core}','build'],check=True)
runtimes = json.loads(run('xcrun','simctl','list','runtimes','-j'))['runtimes']
compatible = [r for r in runtimes if r.get('isAvailable') and r['identifier'].split('.')[-1].startswith('iOS-26')]
if not compatible:
    raise SystemExit('An iOS 26 simulator is required to inspect native Liquid Glass')
runtime = sorted(compatible,key=lambda r:tuple(map(int,r['version'].split('.'))))[-1]
types = json.loads(run('xcrun','simctl','list','devicetypes','-j'))['devicetypes']
device_type = next((d for d in types if d['name']=='iPhone 16'),next(d for d in types if d['name'].startswith('iPhone')))
device = run('xcrun','simctl','create','SideRelay UI',device_type['identifier'],runtime['identifier'])
try:
    run('xcrun','simctl','boot',device)
    run('xcrun','simctl','bootstatus',device,'-b')
    run('xcrun','simctl','status_bar',device,'override','--time','9:41','--batteryState','charged','--batteryLevel','100')
    run('xcrun','simctl','install',device,'build/Preview/Build/Products/Debug-iphonesimulator/SideRelay.app')
    for mode in ['home','pin','account','guide','settings','error','success','large']:
        subprocess.run(['xcrun','simctl','terminate',device,'io.github.corbendallas111.SideRelay'],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL)
        run('xcrun','simctl','launch',device,'io.github.corbendallas111.SideRelay','--ui-preview',mode)
        time.sleep(3)
        run('xcrun','simctl','io',device,'screenshot',str(output/(mode+'.png')))
finally:
    subprocess.run(['xcrun','simctl','shutdown',device],check=False)
print('Rendered home, PIN, account, guide, settings, error, success and maximum Dynamic Type with the UI-only simulator stub')
