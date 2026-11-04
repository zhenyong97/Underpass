#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
preview_root="$project_dir/.build/layout-qa"
mkdir -p "$preview_root" "$project_dir/.build/module-cache"
app_sources=("$project_dir"/Sources/App/*.swift)
app_sources=("${(@)app_sources:#*/UnderpassApp.swift}")
swiftc -disable-sandbox -Onone -target arm64-apple-macosx13.0 -module-cache-path "$project_dir/.build/module-cache" \
  "$project_dir"/Sources/Channels/*.swift "$project_dir/Sources/Runtime/RuntimeIO.swift" "$project_dir/Sources/Runtime/EngineConfiguration.swift" \
  "$project_dir/Sources/Runtime/EngineClient.swift" "$project_dir/Sources/Runtime/RuleTransaction.swift" "$project_dir/Sources/Runtime/SessionController.swift" \
  "${app_sources[@]}" "$project_dir/Tests/LayoutPreviewApp.swift" \
  -framework SwiftUI -framework AppKit -framework SystemConfiguration -o "$preview_root/LayoutPreview"
python3 - "$project_dir" "$preview_root" <<'PY'
from pathlib import Path
import sys,shutil,plistlib,subprocess
root,output=map(Path,sys.argv[1:])
for variant,width,height,count in [('Standard',820,580,2),('Compact',700,480,20),('Dark',820,580,2)]:
 app=output/f'Underpass-{variant}.app'
 (app/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
 resources=app/'Contents/Resources';resources.mkdir(exist_ok=True)
 shutil.copy2(output/'LayoutPreview',app/'Contents/MacOS/LayoutPreview')
 shutil.copytree(root/'Resources/Channels',resources/'Channels',dirs_exist_ok=True)
 data=dict(CFBundleExecutable='LayoutPreview',CFBundleIdentifier='local.underpass.layout-preview.'+variant.lower(),CFBundleName='Underpass '+variant+' Preview',CFBundlePackageType='APPL',LSMinimumSystemVersion='13.0',NSPrincipalClass='NSApplication',NSHighResolutionCapable=True,PreviewWidth=width,PreviewHeight=height,PreviewChannelCount=count)
 if variant=='Dark':data['PreviewAppearance']='dark'
 (app/'Contents/Info.plist').write_bytes(plistlib.dumps(data))
 subprocess.run(['codesign','--force','--sign','-',str(app)],check=True)
 print(app)
PY
