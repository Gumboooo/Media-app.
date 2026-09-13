"""Development-only startup and transport tests of the deployed executable."""
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

BACKEND_FAILURES = {
    41: "library-not-found",
    42: "missing-symbol",
    43: "unsupported-version",
    44: "instance-creation",
    45: "player-creation",
    46: "file-access",
    47: "not-regular-file",
    48: "invalid-path",
    49: "media-creation",
    50: "playback-start",
    51: "invalid-volume",
    52: "worker-spawn",
    53: "command-queue-full",
    54: "worker-disconnected",
    55: "worker-failed",
    56: "playback-start-timeout",
    57: "unclassified-backend-error",
}

results = []
tests = [
    ("startup", []),
    (
        "audio-transport",
        ["--smoke-media", fixture.as_uri(), "--smoke-no-mixer"],
    ),
]
for name, args in tests:
    cmd = [str(bundle / "aperture.exe"), "--smoke-test", *args]
    try:
        run = subprocess.run(cmd, cwd=bundle, env=env, capture_output=True, text=True,
                             encoding="utf-8", errors="replace", timeout=30)
        log = run.stdout + run.stderr
        passed = run.returncode == 0
        if "Binding loop" in log or "ReferenceError" in log or "TypeError" in log:
            passed = False
        result = {"test": name, "exit_code": run.returncode, "passed": passed}
        if not passed and 20 <= run.returncode <= 28:
            result["failed_stage"] = run.returncode - 20
        if not passed and run.returncode in BACKEND_FAILURES:
            result["backend_failure"] = BACKEND_FAILURES[run.returncode]
        results.append(result)
    except subprocess.TimeoutExpired:
        log = "Timed out after 30 seconds; test process was terminated."
        passed = False
        results.append({"test": name, "passed": False, "reason": "timeout"})
    (evidence / (name + ".log")).write_text(log, encoding="utf-8")
    print(name, "PASS" if passed else "FAIL", flush=True)
    if not passed:
        print(results[-1], flush=True)
        print(log, flush=True)
(evidence / "smoke-results.json").write_text(json.dumps(results, indent=2), encoding="utf-8")
sys.exit(0 if all(r["passed"] for r in results) else 1)
