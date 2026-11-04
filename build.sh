#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
output_dir="${1:-${project_dir}/outputs}"
destination="${output_dir}/暗渡.app"
build_cache="${project_dir}/.build/module-cache"
mkdir -p "$output_dir" "$build_cache"
stage_root="$(mktemp -d "$output_dir/.underpass-build.XXXXXX")"
trap 'rm -rf "$stage_root"' EXIT
app_dir="$stage_root/暗渡.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Helpers" "$app_dir/Contents/Resources" "$build_cache"
common=("$project_dir"/Sources/Channels/*.swift "$project_dir/Sources/Runtime/RuntimeIO.swift" "$project_dir/Sources/Runtime/EngineConfiguration.swift")
swiftc -disable-sandbox -O -target arm64-apple-macosx13.0 -module-cache-path "$build_cache" \
  "${common[@]}" "$project_dir/Sources/Runtime/ProxyRestoration.swift" "$project_dir/Sources/Runtime/UnderpassHelper.swift" \
  -framework SystemConfiguration -o "$app_dir/Contents/Helpers/underpass-helper"
swiftc -disable-sandbox -O -target arm64-apple-macosx13.0 -module-cache-path "$build_cache" \
  "${common[@]}" "$project_dir/Sources/Runtime/EngineClient.swift" "$project_dir/Sources/Runtime/RuleTransaction.swift" "$project_dir/Sources/Runtime/SessionController.swift" "$project_dir"/Sources/App/*.swift \
  -framework SwiftUI -framework AppKit -framework SystemConfiguration -o "$app_dir/Contents/MacOS/Underpass"
v2rayn_data_dir="${HOME}/Library/Application Support/v2rayN"
cp "$v2rayn_data_dir/bin/sing_box/sing-box" "$app_dir/Contents/Helpers/sing-box"
cp "$v2rayn_data_dir/bin/xray/xray" "$app_dir/Contents/Helpers/xray"
cp "$project_dir/Info.plist" "$app_dir/Contents/Info.plist"
cp "$project_dir/THIRD_PARTY_NOTICES.txt" "$app_dir/Contents/Resources/THIRD_PARTY_NOTICES.txt"
rm -rf "$app_dir/Contents/Resources/Channels"
ditto "$project_dir/Resources/Channels" "$app_dir/Contents/Resources/Channels"
swift -module-cache-path "$build_cache" "$project_dir/Icon.swift" "$project_dir/.build/AppIcon.iconset"
python3 - "$project_dir/.build/AppIcon.iconset" "$app_dir/Contents/Resources/AppIcon.icns" <<'PY'
import pathlib,struct,sys
folder=pathlib.Path(sys.argv[1]); chunks=[]
for kind,name in [(b'ic07','icon_128x128.png'),(b'ic08','icon_256x256.png'),(b'ic09','icon_512x512.png'),(b'ic10','icon_512x512@2x.png')]:
 data=(folder/name).read_bytes(); chunks.append(kind+struct.pack('>I',len(data)+8)+data)
body=b''.join(chunks); pathlib.Path(sys.argv[2]).write_bytes(b'icns'+struct.pack('>I',len(body)+8)+body)
PY
for item in sing-box xray underpass-helper; do
  codesign --force --sign - "$app_dir/Contents/Helpers/$item"
done
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
python3 - "$app_dir" "$destination" <<'PYINSTALL'
import os,pathlib,shutil,subprocess,sys
stage,dest=map(pathlib.Path,sys.argv[1:])
rollback=dest.parent/'.Underpass-install-rollback.app'
if rollback.exists():
 raise RuntimeError('An interrupted installation remains at '+str(rollback)+'. Restore it before rebuilding.')
if dest.exists():os.rename(dest,rollback)
try:
 os.rename(stage,dest)
 subprocess.run(['codesign','--verify','--deep','--strict',str(dest)],check=True)
except BaseException:
 if dest.exists():shutil.rmtree(dest)
 if rollback.exists():os.rename(rollback,dest)
 raise
else:
 if rollback.exists():shutil.rmtree(rollback)
PYINSTALL
echo "Built: $destination"
