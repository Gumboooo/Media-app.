"""Development-only startup and audio transport tests of the deployed executable."""
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import wave

bundle, evidence = (Path(p).resolve() for p in sys.argv[1:3])
evidence.mkdir(parents=True, exist_ok=True)
fixture = evidence / "generated audio.wav"
# Generated silence: no third-party media and no speaker noise on CI.
with wave.open(str(fixture), "wb") as out:
    out.setparams((1, 2, 48000, 0, "NONE", "not compressed"))
    out.writeframes(struct.pack("<h", 0) * (48000 * 8))
env = dict(os.environ)
# Strip the developer Qt kit from PATH so missing shipped DLLs cannot pass by accident.
env["PATH"] = os.pathsep.join(p for p in env.get("PATH", "").split(os.pathsep) if "qt" not in p.lower())
for key in ("QT_PLUGIN_PATH", "QML2_IMPORT_PATH", "QML_IMPORT_PATH", "APERTURE_LIBVLC_PATH"):
    env.pop(key, None)
# GitHub-hosted Windows runners have no default audio endpoint. Aperture's backend recognizes
# this development-only flag and asks libVLC for its dummy audio sink, preserving the playback
# clock and transport behavior without changing normal user audio output.
env["APERTURE_TEST_DUMMY_AUDIO"] = "1"
results = []
for name, args in [("startup", []), ("audio-transport", ["--smoke-media", fixture.as_uri()])]:
    cmd = [str(bundle / "aperture.exe"), "--smoke-test", *args]
    try:
        run = subprocess.run(cmd, cwd=bundle, env=env, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=30)
        log = run.stdout + run.stderr
        # Smoke.qml reports probe success/failure through Qt.exit(), and main propagates that
        # event-loop result to the Windows process. Console output is diagnostic only because
        # GUI-subsystem release builds are not required to expose QML logging to stdio.
        passed = run.returncode == 0
        if "Binding loop" in log or "ReferenceError" in log or "TypeError" in log:
            passed = False
        results.append({"test": name, "exit_code": run.returncode, "passed": passed})
    except subprocess.TimeoutExpired:
        log = "Timed out after 30 seconds; test process was terminated."
        passed = False
        results.append({"test": name, "passed": False, "reason": "timeout"})
    (evidence / (name + ".log")).write_text(log, encoding="utf-8")
    print(name, "PASS" if passed else "FAIL", flush=True)
    if not passed:
        print(log, flush=True)
(evidence / "smoke-results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
sys.exit(0 if all(r["passed"] for r in results) else 1)
