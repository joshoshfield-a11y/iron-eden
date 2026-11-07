#!/usr/bin/env python3
"""IRON EDEN beta testers — read-only QC harness (see docs/BETA-TESTERS.md).

Runs the headless auto test once against a frozen snapshot of the tree,
audits the snapshot + the built APK, and writes a per-tester report to qa/.
Exits 0 on PASS, 1 on any tester FAIL, 2 when skipped (loop lock held).

Usage: python3 prototype/tools/beta-testers.py [--no-test]
  --no-test skips the headless game run (tree/APK checks only).
"""
import os, re, struct, subprocess, sys, zipfile, datetime, argparse
import shutil, tempfile, hashlib

HOME = os.path.expanduser("~")
PROTO = os.path.join(HOME, "workspace/iron-eden/prototype")
GODOT = os.path.join(HOME, "tools/godot/godot")
QA = os.path.join(HOME, "workspace/iron-eden/qa")
APK = os.path.join(PROTO, "build/iron-eden-slice.apk")
TEST_TIMEOUT = 600

results = []  # (tester, check, status, evidence)

def check(tester, name, ok, evidence=""):
    results.append((tester, name, "PASS" if ok else "FAIL", evidence))

def warn(tester, name, evidence=""):
    results.append((tester, name, "WARN", evidence))

def read(p):
    with open(p, encoding="utf-8", errors="replace") as f:
        return f.read()

def png_size(p):
    with open(p, "rb") as f:
        head = f.read(33)
    if head[:8] != b"\x89PNG\r\n\x1a\n" or len(head) < 33:
        return None
    return struct.unpack(">II", head[16:24])

def run_all(tree, main_gd, preset_version, preset_code, no_test):
    # ---------- Crash: headless auto test on the snapshot ----------
    test_log = ""
    if not no_test:
        try:
            r = subprocess.run([GODOT, "--headless", "--path", tree,
                                "--", "--iron-eden-test"],
                               capture_output=True, text=True, timeout=TEST_TIMEOUT)
            test_log = r.stdout + r.stderr
        except subprocess.TimeoutExpired:
            test_log = "TIMEOUT after %ss" % TEST_TIMEOUT
        check("Crash", "auto test completes (no hang)",
              "TIMEOUT" not in test_log,
              test_log[-200:] if "TIMEOUT" in test_log else "")
        check("Crash", "IRON EDEN AUTO TEST: PASS",
              "IRON EDEN AUTO TEST: PASS" in test_log, "")
        check("Crash", "zero SCRIPT ERROR lines",
              "SCRIPT ERROR" not in test_log,
              "found" if "SCRIPT ERROR" in test_log else "")
    else:
        warn("Crash", "headless test skipped (--no-test)", "")

    # ---------- Rules: version stamp + test fails ----------
    stamp_m = re.search(r'IRON EDEN v([0-9.]+)', main_gd)
    stamp_version = stamp_m.group(1) if stamp_m else "?"
    check("Rules", "in-code version stamp matches export preset",
          stamp_version == preset_version,
          "stamp=%s preset=%s" % (stamp_version, preset_version))
    if test_log:
        check("Rules", "zero TEST FAIL lines",
              "TEST FAIL" not in test_log, "")

    # ---------- Pixel: texture audit ----------
    gd_files = [os.path.join(tree, "scripts", f) for f in
                os.listdir(os.path.join(tree, "scripts")) if f.endswith(".gd")]
    refs = set()
    for f in gd_files:
        refs.update(re.findall(r'res://(sprites/[A-Za-z0-9_/.\-]+\.png)', read(f)))
    missing = [r for r in refs if not os.path.exists(os.path.join(tree, r))]
    check("Pixel", "all code-referenced textures exist (%d refs)" % len(refs),
          not missing, "missing: %s" % missing[:5])
    pngs, bad_import, bad_png = [], [], []
    for root, _dirs, files in os.walk(os.path.join(tree, "sprites")):
        for f in files:
            if f.endswith(".png"):
                p = os.path.join(root, f)
                pngs.append(p)
                if not os.path.exists(p + ".import"):
                    bad_import.append(os.path.relpath(p, tree))
                sz = png_size(p)
                if sz is None or sz[0] < 1 or sz[1] < 1 or sz[0] > 4096 or sz[1] > 4096:
                    bad_png.append(os.path.relpath(p, tree))
    check("Pixel", "every shipped PNG has a .import file (%d PNGs)" % len(pngs),
          not bad_import, "missing .import: %s" % bad_import[:5])
    check("Pixel", "every PNG parses with sane dimensions",
          not bad_png, "bad: %s" % bad_png[:5])
    check("Pixel", "Pass 34/35 art dirs present",
          os.path.isdir(os.path.join(tree, "sprites/p34")) and
          os.path.isdir(os.path.join(tree, "sprites/p35")), "")
    uv_m = re.search(r'_ground_mat\.uv1_scale\s*=\s*Vector3\(([\d.]+),\s*([\d.]+)', main_gd)
    check("Pixel", "ground repeat is Pass 39 value (2x, not 6x)",
          bool(uv_m) and float(uv_m.group(1)) == 2.0 and float(uv_m.group(2)) == 2.0,
          "uv1_scale=%s" % (uv_m.group(0) if uv_m else "not found"))

    # ---------- Flow: HUD budget + button + hint audit ----------
    def const(name):
        mm = re.search(r'const %s\s*:?=?\s*([\d.]+)' % name, main_gd)
        return float(mm.group(1)) if mm else None
    top = const("P40_TOP_H") or const("P20_TOP_H") or 0
    bottom = const("P40_BOTTOM_H") or const("P20_BOTTOM_H") or 0
    msg = const("P40_MSG_H") or 0
    preview = const("P40_PREVIEW_H") or 0
    typical, worst = top + bottom, top + bottom + msg + preview
    check("Flow", "typical HUD chrome <= 208 px", typical <= 208,
          "top=%s bottom=%s typical=%s" % (top, bottom, typical))
    check("Flow", "worst-case HUD chrome <= 286 px", worst <= 286,
          "worst=%s (msg=%s preview=%s)" % (worst, msg, preview))
    check("Flow", "icon buttons use expand_icon (Pass 40 bug class)",
          "expand_icon" in main_gd,
          "expand_icon present" if "expand_icon" in main_gd else "not found")
    # WASD check ignores comments and the test assertions that mention it;
    # only real hint/code text counts.
    code_lines = [ln for ln in main_gd.splitlines()
                  if "_check(" not in ln and not ln.strip().startswith("#")]
    check("Flow", "touch hint has no WASD",
          not any("WASD" in ln for ln in code_lines), "")
    build_w = re.search(r'_build_bar\.size\s*=\s*Vector2\(([\d.]+)', main_gd)
    check("Flow", "build bar fits a phone viewport width",
          bool(build_w) and float(build_w.group(1)) <= 1600,
          "build bar width=%s" % (build_w.group(1) if build_w else "?"))

    # ---------- APK audit ----------
    apk_ok, apk_ev = False, ""
    if os.path.exists(APK):
        md5 = hashlib.md5(open(APK, "rb").read()).hexdigest()
        env = dict(os.environ, JAVA_HOME=os.path.join(HOME, "jdk17"),
                   PATH=os.path.join(HOME, "jdk17/bin") + ":" + os.environ["PATH"])
        v = subprocess.run([os.path.join(HOME, "android-sdk/build-tools/36.1.0/apksigner"),
                            "verify", APK], capture_output=True, text=True, env=env)
        b = subprocess.run([os.path.join(HOME, "android-sdk/build-tools/36.1.0/aapt2"),
                            "dump", "badging", APK], capture_output=True, text=True)
        pkg = re.search(r"package: name='([^']+)' versionCode='([^']+)' versionName='([^']+)'",
                        b.stdout)
        apk_ok = v.returncode == 0 and bool(pkg)
        apk_ev = "md5=%s pkg=%s" % (md5, pkg.group(0) if pkg else "unparsed")
        check("Rules", "APK badging matches preset (package/version/code)",
              bool(pkg) and pkg.group(2) == preset_code and pkg.group(3) == preset_version,
              apk_ev)
    check("Crash", "built APK passes apksigner verify", apk_ok, apk_ev)
    zips = [f for f in os.listdir(os.path.join(HOME, "workspace/your_files"))
            if f.startswith("iron-eden-v%s-" % preset_version)]
    zip_ok = False
    if zips:
        try:
            zip_ok = zipfile.ZipFile(
                os.path.join(HOME, "workspace/your_files", zips[0])).testzip() is None
        except Exception:
            zip_ok = False
    check("Crash", "deliverable zip for this version is intact", zip_ok,
          zips[0] if zips else "no zip found")

    # ---------- Report ----------
    fails = [r for r in results if r[2] == "FAIL"]
    overall = "FAIL" if fails else "PASS"
    stamp_now = datetime.datetime.now().strftime("%Y%m%d-%H%M")
    report_path = os.path.join(QA, "beta-report-v%s-%s.md" % (preset_version, stamp_now))
    lines = ["# Beta test report — IRON EDEN v%s (code %s)" % (preset_version, preset_code),
             "", "Overall: **%s**" % overall,
             "Build under test: preset v%s code %s, APK on disk %s" % (
                 preset_version, preset_code, apk_ev),
             "Test log: %s" % ("headless auto test run this session on a frozen snapshot"
                               if test_log else "skipped (--no-test)"),
             ""]
    for tester in ("Pixel", "Crash", "Rules", "Flow"):
        lines.append("## %s" % tester)
        for _t, name, status, ev in results:
            if _t == tester:
                lines.append("- [%s] %s%s" % (status, name, (" — " + ev) if ev else ""))
        lines.append("")
    lines += ["## Device-only (still the user's phone job)",
              "- In-hand look, readability at arm's length, walk-cycle read",
              "- Touch feel, button readability, consolidated-HUD roominess",
              "- Real S25 fps (sandbox numbers are never device fps)",
              ""]
    with open(report_path, "w") as f:
        f.write("\n".join(lines))
    print("BETA REPORT: %s -> %s" % (overall, report_path))
    for _t, name, status, ev in results:
        print("[%s] %s: %s%s" % (status, _t, name, (" — " + ev) if ev else ""))
    return 1 if fails else 0

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--no-test", action="store_true")
    args = ap.parse_args()
    os.makedirs(QA, exist_ok=True)
    preset = read(os.path.join(PROTO, "export_presets.cfg"))
    m = re.search(r'version/name="([^"]+)"', preset)
    preset_version = m.group(1) if m else "?"
    m = re.search(r'version/code=(\d+)', preset)
    preset_code = m.group(1) if m else "?"
    # Never audit a moving tree: if a loop worker holds the lock, the tree
    # is mid-edit and any verdict would be a race artifact (this bit the
    # first run: Pass 46 took the lock at 14:05, harness ran at 14:14).
    lock_m = re.search(r'^Lock:\s*(.*)$',
                       read(os.path.join(HOME, "workspace/iron-eden/docs/LOOP-STATE.md")),
                       re.M)
    if lock_m and "IN_PROGRESS" in lock_m.group(1):
        stamp_now = datetime.datetime.now().strftime("%Y%m%d-%H%M")
        with open(os.path.join(QA, "beta-report-SKIPPED-%s.md" % stamp_now), "w") as f:
            f.write("# Beta test report — SKIPPED\n\nLoop worker holds the lock "
                    "(%s). Tree is mid-edit; no verdict issued. Re-run when "
                    "the lock clears.\n" % lock_m.group(1))
        print("BETA REPORT: SKIPPED — loop lock held (%s)" % lock_m.group(1))
        return 2
    snap = tempfile.mkdtemp(prefix="iron-eden-beta-",
                            dir=os.path.join(HOME, "workspace/iron-eden"))
    try:
        shutil.copytree(PROTO, os.path.join(snap, "prototype"),
                        ignore=shutil.ignore_patterns("build"))
        snap_proto = os.path.join(snap, "prototype")
        return run_all(snap_proto, read(os.path.join(snap_proto, "scripts/main.gd")),
                       preset_version, preset_code, args.no_test)
    finally:
        shutil.rmtree(snap, ignore_errors=True)

if __name__ == "__main__":
    sys.exit(main())
