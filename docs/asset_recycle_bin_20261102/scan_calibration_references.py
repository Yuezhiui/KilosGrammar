from pathlib import Path
from collections import defaultdict
import json, hashlib, re
root=Path.cwd()
output=root/'docs/asset_recycle_bin_20261102'
cal=root/'Components/Gameplay/Calibration'
skip={'.git','.godot','.venv','venv','node_modules','release','out','build','dist','__pycache__'}
source_ext={'.tscn','.gd','.tres','.gdshader','.cfg','.ps1','.py','.json','.md','.txt','.toml','.ini'}
code_ext={'.tscn','.gd','.tres','.gdshader','.cfg','.ps1'}
sources=[]
for p in root.rglob('*'):
    if not p.is_file() or any(part.lower() in skip for part in p.relative_to(root).parts): continue
    if output in p.parents: continue
    if p.suffix.lower() not in source_ext: continue
    if p.stat().st_size>2_500_000: continue
    try: text=p.read_text(encoding='utf-8-sig',errors='replace')
    except Exception: continue
    sources.append((p.relative_to(root).as_posix(),text))
assets=sorted(cal.rglob('*.png'))
index={}
for asset in assets:
    relative=asset.relative_to(root).as_posix()
    path='res://'+relative
    uid=''
    imp=Path(str(asset)+'.import')
    if imp.exists():
        match=re.search(r'uid="(uid://[^"]+)"',imp.read_text(encoding='utf-8',errors='replace'))
        if match: uid=match.group(1)
    per_kind=defaultdict(list)
    basename=asset.name
    for filename, text in sources:
        # Count references only from this asset path or exact filename in same
        # calibration folder context; don't equate similarly named PNGs elsewhere.
        exact=path in text
        shortened=relative in text
        uid_used=uid and uid in text
        # Dynamic ROOT + filename is uncertain: mark separately, but NEVER
        # misreport it as a proven scene/script dependency. Also do not match
        # broad directory strings such as Calibration/ to all sibling PNGs.
        dynamic=(not exact and not shortened and not uid_used
            and basename in text and 'Components/Gameplay/Calibration/' in text)
        if not (exact or shortened or uid_used or dynamic): continue
        kind='production' if filename.startswith(('ui/','database/')) or (filename.endswith('.tscn') and not filename.startswith('tools/')) else ('qa' if filename.startswith('tools/') else 'docs_or_other')
        keys=[]
        if exact or shortened: keys.append('path')
        if uid_used: keys.append('uid')
        if dynamic: keys.append('possible_dynamic')
        per_kind['possible_dynamic' if dynamic else kind].append({'file':filename,'match':keys})
    if imp.exists():
        index[relative]={'size':asset.stat().st_size,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest(),'import_path':imp.relative_to(root).as_posix(),'uid':uid,'references':dict(per_kind)}
    else:
        index[relative]={'size':asset.stat().st_size,'sha256':hashlib.sha256(asset.read_bytes()).hexdigest(),'import_path':None,'uid':uid,'references':dict(per_kind)}
full={
 'as_of':'2026-11-02',
 'scope':'All live Components/Gameplay/Calibration PNG and PNG.import; whole repository textual scene/script/QA/doc search',
 'files_scanned':len(sources),
 'calibration_png_count':len(assets),
 'assets':index
}
(output/'calibration_reference_audit.json').write_text(json.dumps(full,ensure_ascii=False,indent=2)+'\n',encoding='utf-8')
# Intentionally avoid generating .csv or raster thumbnails inside res://docs:
# Godot's editor can import those and create distracting .import/.translation
# files during release preparation. JSON is the only machine-readable output.
print('scanned',len(sources),'calibration pngs',len(assets))
for path,row in index.items():
 refs=row['references']
 print(Path(path).name,'prod',len(refs.get('production',[])),'qa',len(refs.get('qa',[])),'docs',len(refs.get('docs_or_other',[])),'uncertain',len(refs.get('possible_dynamic',[])), 'uid',row['uid'])
