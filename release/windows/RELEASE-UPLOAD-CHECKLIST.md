# KilosGrammar Windows GitHub Release readiness — 2026-10-30

## 30 October 2026 native release-candidate update

**Native, locally buildable package: YES. Public classroom release: NOT YET.**
The older developer-preview-only assessment below is historical. A full
release-template Windows x64 EXE/PCK and real offline prerequisites have now
been obtained and staged, and the genuine 82-file release folder validates.

- [x] Exact official Godot 4.7.2 Windows release/debug templates: archive
  1,281,349,702 bytes, SHA-512 matched against official Godot checksums.
- [x] Official signed Python 3.11.9 Windows x64 installer, SHA-256
  5EE42C4EEE1E6B4464BB23722F90B45303F79442DF63083F05322F1785F5FDDE.
- [x] Official signed EnterpriseDB PostgreSQL 18.6 x64 installer, SHA-256
  227E2BC08091B4C2B8338C7D61B11D057F895711480B006F90BFCFCD2410A58A.
- [x] 44 Windows CPython 3.11 wheels including CPU torch/torchvision.
  Offline pip no-index dependency resolution PASS, zero network fallback.
- [x] Clean local QA Python 3.11 venv installed all 44 wheels strictly with
  no-index and imported cv2, torch, torchvision, ultralytics, lap and psycopg.
  The packaged yolo26n-pose.pt checkpoint loaded and ran CPU prediction on
  one synthetic 640x480 frame without using a camera or downloading weights.
  This checks the local build machine only, not second-PC performance.
- [x] Actual 47-entry offline/manifest.json, tested SHA-256 inventory.
- [x] Build-OfflineRelease.ps1 preflight AND production export PASS.
  Real EXE: 109,319,680 bytes, SHA-256
  64E37A4E8B2011BB9B8081A8171628B1E8C47FA244490B62B0D234F672542F1F.
  Real PCK: 142,296,688 bytes, SHA-256
  F611FA1A07179D6B353DF5496E836F5E7C3F33BB916FD32407F19AA6B372A5C2.
- [x] 82 release files validated by Test-ReleasePackage.ps1; read-only launch
  preflight PASS. No game, camera or student DB accessed by that preflight.
- [x] OFFLINE-CANDIDATE ZIP, **not clean-laptop accepted**:
  release/windows/out/KilosGrammar-v0.3.0-beta.1-OFFLINE-CANDIDATE-NOT-CLEAN-PC-TESTED-win-x64.zip
  is 974,927,095 bytes; SHA-256
  E7ADC2BCC0B25F7116D44EB1D388078D414BCBB31BFEBC4237C804C43162B399;
  all 83 ZIP entries match their manifests.
- [x] Inno Setup 6 compiler obtained from signed official setup; QA installer
  compiled, silently installed to a fresh path containing spaces, verified
  82 installed payload SHA-256s, then silently uninstalled. Application folder
  removed, independent per-user test data preserved. No DB/PG service touched.
- [x] Official non-QA Inno Setup.exe **candidate** compiled and SHA sidecar
  verified: release/windows/out/KilosGrammar-v0.3.0-beta.1-OFFLINE-CANDIDATE-NOT-CLEAN-PC-TESTED-Setup.exe,
  953,524,623 bytes, SHA-256
  81935FB42252CC9E436E05B07992A3C4723F895E0042C8CBE600B0B70592018F.
  Authenticode status: **NotSigned**; Windows publisher warning expected.
- [ ] Formal commercial/noncommercial rights and third-party license review:
  Ultralytics model and code (AGPL or separate license), original game assets,
  fonts, narration, PostgreSQL installer and all bundled wheels. Downloading
  signed files proves authenticity, **not permission to republish**.
- [ ] Real clean Windows x64 standard-user laptop test **with Internet off**:
  native executable, Python venv setup, PostgreSQL setup under school admin
  control, YOLO camera calibration, three rounds, student profiles and score
  persistence, leaderboard CSV full export/import recovery and reboot.
- [ ] GitHub release created and .zip/.exe/checksum assets uploaded. The
  connected GitHub tool supports reading Releases (currently []) and pushing
  source, but no authenticated binary Release asset-upload operation; do not
  bypass credential access restrictions.

The school administrator must explicitly install/configure Python/PostgreSQL
before running Setup Offline.cmd. An Inno installer that copies files is
not an automatic PostgreSQL service or complete deployment acceptance.

## Historical developer-preview evaluation (superseded build inputs)

**Original status before official dependencies were obtained: BLOCKED.**

Do **not** label the current developer preview as a school-ready or standalone
portable game. The current preview's EXE is a repackaged Godot 4.7.2 editor
binary accompanied by a real exported PCK, not an official release-template
build. It does not contain a working target-local Python/YOLO or PostgreSQL
offline installer/runtime. The developer machine's existing PostgreSQL or
Python installation must never be assumed on the next computer.

## What is genuinely available today

- [x] `release/windows/out/KilosGrammar-v0.3.0-beta.1-EDITOR-PREVIEW-NOT-DEPLOYABLE-win-x64.zip`
- [x] `release/windows/out/KilosGrammar-v0.3.0-beta.1-EDITOR-PREVIEW-NOT-DEPLOYABLE-win-x64.zip.sha256.txt`
- [x] ZIP integrity tested: every one of **28** entries matches the verified
  developer-preview SHA-256 inventory; the full ZIP SHA-256 is
  `DC7F07BD67F6D30BC17412C1E3A72BEB42AFB6D2AD9B4F70389D2BC31ABE191F`
  and length is `228113679` bytes.
- [x] ZIP extracted into a fresh path containing spaces; actual files copied
  to a new `%LOCALAPPDATA%\Programs\Kilos Grammar Release QA ...` location.
  A read-only launch preflight, simulated installation, overwrite/Program
  Files refusal, unknown-file uninstall refusal, uninstall, and preservation
  of external test user data all passed.
- [x] User-provided `release/windows/branding/KILOSGRAMMAR.ico` preserved,
  SHA-256 `A6C85F3056F61D9043794E4B96912AFBB5A9AAC54C893995C7F0417B4DB7F4D8`.
  It is configured for the *future* Windows release export. The preview editor
  binary still uses the editor executable icon.
- [x] ZIP excludes any `.venv`, PostgreSQL cluster, database file, student
  score records, DPAPI credential XML, camera footage, and development export
  template. Existing app folders and global user data were not modified.
- [x] No commit, push, GitHub Release upload, camera run, PostgreSQL login,
  database query, service restart, or deployment performed.

## Before calling any ZIP or Setup.exe a functioning offline release

- [ ] Download/review the exact official **Godot 4.7.2.stable Windows x64**
  release and debug templates, place them in
  `%APPDATA%\Godot\export_templates\4.7.2.stable`, and run the builder's
  template validation. The official complete templates archive is about
  **1,281,349,702 bytes** based on a successful October 30 HTTP HEAD check.
  Downloading this alone does NOT satisfy the Python/PostgreSQL requirements.
- [ ] Review licenses and supply the full **CPython 3.11 x64 offline installer**,
  **PostgreSQL 18 x64 offline installer** and all required redistribution terms.
- [ ] Stage a complete vetted **Windows CPython 3.11 wheelhouse** including
  Ultralytics, compatible Torch + TorchVision, OpenCV, LAP, Psycopg binary and
  every transitive dependency. Validate strictly with `--no-index`, without
  downloading to the school computer.
- [ ] Verify `yolo26n-pose.pt` origin, SHA-256, license and redistribution
  permissions. Verify all game images, fonts and audio have distribution rights.
- [ ] Run `Stage-OfflinePrerequisites.ps1` successfully and verify real
  `release/windows/offline/manifest.json` created from genuine inputs.
- [ ] Run `Build-OfflineRelease.ps1 -PreflightOnly` and then the actual export.
  Require real **Godot Windows release-template EXE** plus PCK, model, Python
  dependencies, database scripts/migrations, offline inputs and
  `manifest.json` verifying all shipped bytes. Never create a fake manifest.
- [ ] On a CLEAN second laptop with Internet disabled, fresh standard Windows
  user, and no developer environment, install to a **fresh writable per-user**
  `%LOCALAPPDATA%\Programs\KilosGrammar` directory (not `Program Files`).
  Run `Setup Offline.cmd` and verify Python3.11 venv/imports without network.
- [ ] Have an administrator review PostgreSQL 18 installation/service, any
  existing port **5432** occupant, database name/role/backups and schema before
  touching records. Review port **18765** occupancy and do not stop or replace
  unrelated processes. DPAPI credentials must stay per-user in LocalAppData.
- [ ] Reboot that other laptop and prove real `KilosGrammar.exe` launch, local
  service health, real webcam permission, on-device YOLO inference, stable
  single-student calibration, Catch/Balloon/Human Plane full rounds, student
  registration, persistent scores, leaderboard and CSV import/export/delete.
- [ ] Test repair/launch, non-admin path containing spaces, port collisions,
  bad/missing runtime, and safe uninstall that preserves student records.
- [ ] Only after all checks, build and TEST a genuine installation experience
  (`Setup.exe` using an actually available Inno Setup/NSIS/WiX tool, or a
  documented equivalent). IExpress alone is an EXE self-extractor, not proof
  of an installed, functioning offline app. No verified installer exists yet.
- [ ] Create an appropriately named non-preview GitHub release tag/version;
  upload the **verified** installable ZIP, installer, checksums and release
  notes. Use the repo's `.../releases/new` interface with authorized credentials.
  Publishing is **not** authorized in the current packaging worker task.

## For internal preview ZIP reproduction only

```powershell
& .\release\windows\Test-PreviewPackage.ps1 `
    -PackageRoot '.\release\windows\staging\KilosGrammar-EDITOR-PREVIEW-win-x64-releaseQA'
& .\release\windows\Build-ReviewedZip.ps1 -AllowPreview
& .\release\windows\Test-ReviewedZip.ps1 `
    -ZipPath '.\release\windows\out\KilosGrammar-v0.3.0-beta.1-EDITOR-PREVIEW-NOT-DEPLOYABLE-win-x64.zip' `
    -PackageRoot '.\release\windows\staging\KilosGrammar-EDITOR-PREVIEW-win-x64-releaseQA' -AllowPreview
```

ZIP building is intentionally **no-overwrite**. Archive contents, checksum and
integrity are checked against the local developer-preview manifest; this is
not a substitute for a code-signing certificate or clean-device acceptance.
