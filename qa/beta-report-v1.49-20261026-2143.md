# Beta test report — IRON EDEN v1.49 (code 50)

Overall: **PASS**
Build under test: preset v1.49 code 50, APK on disk md5=58d6f0d0c40efca17912dc65948932c6 pkg=package: name='com.dogbyte.ironeden' versionCode='50' versionName='1.49'
Test log: headless auto test run this session on a frozen snapshot

## Pixel
- [PASS] all code-referenced textures exist (19 refs) — missing: []
- [PASS] every shipped PNG has a .import file (264 PNGs) — missing .import: []
- [PASS] every PNG parses with sane dimensions — bad: []
- [PASS] Pass 34/35 art dirs present
- [PASS] ground repeat is Pass 39 value (2x, not 6x) — uv1_scale=_ground_mat.uv1_scale = Vector3(2, 2

## Crash
- [PASS] auto test completes (no hang)
- [PASS] IRON EDEN AUTO TEST: PASS
- [PASS] zero SCRIPT ERROR lines
- [PASS] built APK passes apksigner verify — md5=58d6f0d0c40efca17912dc65948932c6 pkg=package: name='com.dogbyte.ironeden' versionCode='50' versionName='1.49'
- [PASS] deliverable zip for this version is intact — iron-eden-v1.49-pass47.zip

## Rules
- [PASS] in-code version stamp matches export preset — stamp=1.49 preset=1.49
- [PASS] zero TEST FAIL lines
- [PASS] APK badging matches preset (package/version/code) — md5=58d6f0d0c40efca17912dc65948932c6 pkg=package: name='com.dogbyte.ironeden' versionCode='50' versionName='1.49'

## Flow
- [PASS] typical HUD chrome <= 208 px — top=84.0 bottom=124.0 typical=208.0
- [PASS] worst-case HUD chrome <= 286 px — worst=278.0 (msg=30.0 preview=40.0)
- [PASS] icon buttons use expand_icon (Pass 40 bug class) — expand_icon present
- [PASS] touch hint has no WASD
- [PASS] build bar fits a phone viewport width — build bar width=762.0

## Device-only (still the user's phone job)
- In-hand look, readability at arm's length, walk-cycle read
- Touch feel, button readability, consolidated-HUD roominess
- Real S25 fps (sandbox numbers are never device fps)
