#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h}"
output_dir="$project_dir/outputs"
app_dir="$output_dir/暗渡.app"
codesign --verify --deep --strict "$app_dir"
release_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_dir/Contents/Info.plist")"
cp "$project_dir/README.md" "$output_dir/暗渡-使用说明.md"
ditto -c -k --sequesterRsrc --keepParent "$app_dir" "$output_dir/Underpass-macOS-${release_version}.zip"
python3 - "$project_dir" "$release_version" <<'PY'
import pathlib,sys,zipfile,hashlib,shutil,re
root=pathlib.Path(sys.argv[1]);version=sys.argv[2]
assert re.fullmatch(r'\d+\.\d+\.\d+',version)
files=[]
for name in ['Sources','Tests','Resources','Docs']:
 files.extend(p for p in (root/name).rglob('*') if p.is_file() and not any(part in {'.DS_Store','__pycache__'} for part in p.parts))
files.extend(root/name for name in ['build.sh','test.sh','package.sh','Info.plist','Icon.swift','README.md','PRODUCT.md','DESIGN.md','THIRD_PARTY_NOTICES.txt','.gitignore'])
with zipfile.ZipFile(root/f'outputs/Underpass-Source-{version}.zip','w',zipfile.ZIP_DEFLATED) as z:
 for p in sorted(files):z.write(p,pathlib.Path('Underpass')/p.relative_to(root))
paths=[root/'outputs'/n for n in [f'Underpass-macOS-{version}.zip',f'Underpass-Source-{version}.zip']]
manifest=root/f'outputs/SHA256SUMS-{version}.txt'
manifest.write_text(''.join(hashlib.sha256(p.read_bytes()).hexdigest()+'  '+p.name+'\n' for p in paths))
shutil.copy2(manifest,root/'outputs/SHA256SUMS.txt')
print('Archives ready:',root/'outputs')
PY
