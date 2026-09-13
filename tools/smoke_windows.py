"""Development-only startup and transport tests of the deployed executable."""
import ctypes
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


def libvlc_media_probe():
    """Independently exercise the packaged libVLC path/location constructors.

    This deliberately bypasses Aperture's Rust FFI. If both layers fail identically, the problem
    is in libVLC/path semantics or packaging; if ctypes succeeds, our Rust boundary is suspect.
    """
    report = {"fixture": str(fixture), "fixture_uri": fixture.as_uri(), "cases": []}
    dll_dir = None
    instance = None
    try:
        if hasattr(os, "add_dll_directory"):
            dll_dir = os.add_dll_directory(str(bundle))
        vlc = ctypes.CDLL(str(bundle / "libvlc.dll"))

        vlc.libvlc_new.argtypes = [ctypes.c_int, ctypes.POINTER(ctypes.c_char_p)]
        vlc.libvlc_new.restype = ctypes.c_void_p
        vlc.libvlc_release.argtypes = [ctypes.c_void_p]
        vlc.libvlc_release.restype = None
        vlc.libvlc_media_new_path.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        vlc.libvlc_media_new_path.restype = ctypes.c_void_p
        vlc.libvlc_media_new_location.argtypes = [ctypes.c_void_p, ctypes.c_char_p]
        vlc.libvlc_media_new_location.restype = ctypes.c_void_p
        vlc.libvlc_media_release.argtypes = [ctypes.c_void_p]
        vlc.libvlc_media_release.restype = None
        vlc.libvlc_errmsg.argtypes = []
        vlc.libvlc_errmsg.restype = ctypes.c_char_p
        clearerr = getattr(vlc, "libvlc_clearerr", None)
        if clearerr is not None:
            clearerr.argtypes = []
            clearerr.restype = None

        options = (ctypes.c_char_p * 3)(
            b"--no-video-title-show",
            b"--no-metadata-network-access",
            b"--aout=dummy",
        )
        instance = vlc.libvlc_new(len(options), options)
        if not instance:
            raw = vlc.libvlc_errmsg()
            report["instance_error"] = raw.decode("utf-8", "replace") if raw else "unknown"
            return report

        native = str(fixture)
        cases = [
            ("path-native", vlc.libvlc_media_new_path, native),
            ("path-forward-slash", vlc.libvlc_media_new_path, native.replace("\\", "/")),
            ("location-file-uri", vlc.libvlc_media_new_location, fixture.as_uri()),
        ]
        for name, constructor, value in cases:
            if clearerr is not None:
                clearerr()
            media = constructor(instance, value.encode("utf-8"))
            raw = vlc.libvlc_errmsg()
            case = {"case": name, "value": value, "created": bool(media)}
            if raw:
                case["libvlc_error"] = raw.decode("utf-8", "replace")
            report["cases"].append(case)
            if media:
                vlc.libvlc_media_release(media)
    except Exception as exc:  # Diagnostic only; never hide the original smoke failure.
        report["probe_exception"] = repr(exc)
    finally:
        if instance:
            try:
                vlc.libvlc_release(instance)
            except Exception:
                pass
        if dll_dir is not None:
            dll_dir.close()
    return report


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
        if not passed and run.returncode == 49:
            probe = libvlc_media_probe()
            result["libvlc_media_probe"] = probe
            (evidence / "libvlc-media-probe.json").write_text(
                json.dumps(probe, indent=2), encoding="utf-8"
            )
            print("libVLC media probe:", json.dumps(probe, indent=2), flush=True)
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
