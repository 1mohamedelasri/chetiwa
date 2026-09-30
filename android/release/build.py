#!/usr/bin/env python3
"""Build and verify an upload-signed AAB; never upload or publish it."""

import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import urllib.request
from urllib.parse import urlparse
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[2]
FLUTTER_VERSION = "3.47.1"
BUNDLETOOL_VERSION = "1.18.2"
BUNDLETOOL_SHA256 = "378b5434cd1378bef6b2bc527b8c7f0ff2584b273830335bce54d6d0813c8584"
BUNDLE = ROOT / "build/app/outputs/bundle/release/app-release.aab"
ANDROID_NS = "{http://schemas.android.com/apk/res/android}"


def fail(message):
    raise SystemExit(message)


def capture(command):
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        # Do not echo arbitrary tool output: a manifest can contain API keys.
        fail(f"{Path(command[0]).name} failed (exit {result.returncode}).")
    return result.stdout.strip()


def validate_inputs(version, build_number, api_url):
    if not re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version):
        fail("Release version must use MAJOR.MINOR.PATCH.")
    if not re.fullmatch(r"[1-9][0-9]*", build_number) or int(build_number) > 2100000000:
        fail("Build number must be a positive Play-compatible integer.")
    try:
        url = urlparse(api_url)
        host = url.hostname or ""
        port = url.port
    except ValueError:
        fail("API URL is invalid.")
    if (url.scheme != "https" or not host or url.username or url.password
            or url.query or url.fragment or url.path not in ("", "/")
            or port not in (None, 443) or host == "localhost"
            or host.endswith((".localhost", ".local"))):
        fail("API URL must be a public HTTPS origin on port 443.")
    try:
        address = ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        if not address.is_global:
            fail("API URL must not use a private address.")


def signature(bundle=None):
    properties = ROOT / "android/key.properties"
    if not properties.is_file():
        fail("Missing android/key.properties and upload key; no release was built.")
    command = ["java", str(ROOT / "android/release/VerifyUploadSignature.java"), str(properties)]
    if bundle:
        command.append(str(bundle))
    fingerprint = capture(command)
    if not re.fullmatch(r"[0-9a-f]{64}", fingerprint):
        fail("Unexpected upload-signature verification result.")
    return fingerprint


def bundletool():
    target = ROOT / f"build/release-tools/bundletool-{BUNDLETOOL_VERSION}.jar"
    if not target.is_file():
        target.parent.mkdir(parents=True, exist_ok=True)
        url = ("https://github.com/google/bundletool/releases/download/"
               f"{BUNDLETOOL_VERSION}/bundletool-all-{BUNDLETOOL_VERSION}.jar")
        temporary = target.with_suffix(".download")
        try:
            with urllib.request.urlopen(url, timeout=60) as response:
                with temporary.open("wb") as output:
                    while chunk := response.read(1024 * 1024):
                        output.write(chunk)
            if hashlib.sha256(temporary.read_bytes()).hexdigest() != BUNDLETOOL_SHA256:
                fail("Downloaded bundletool checksum does not match the pinned release.")
            temporary.replace(target)
        finally:
            temporary.unlink(missing_ok=True)
    if hashlib.sha256(target.read_bytes()).hexdigest() != BUNDLETOOL_SHA256:
        fail("Cached bundletool checksum does not match the pinned release.")
    return ["java", "-jar", str(target)]


def validate_manifest(xml, version, build_number):
    manifest = ET.fromstring(xml)
    application = manifest.find("application")
    sdk = manifest.find("uses-sdk")
    if manifest.get("package") != "com.ezplatforms.chetiwa":
        fail("Unexpected package ID in AAB.")
    if (manifest.get(ANDROID_NS + "versionName") != version
            or manifest.get(ANDROID_NS + "versionCode") != build_number):
        fail("AAB version does not match the requested release.")
    if sdk is None or int(sdk.get(ANDROID_NS + "targetSdkVersion", "0")) < 36:
        fail("AAB must target Android API 36 or later.")
    if application is None or application.get(ANDROID_NS + "debuggable", "false") != "false":
        fail("AAB must contain a non-debuggable application.")
    metadata = {item.get(ANDROID_NS + "name"): item.get(ANDROID_NS + "value", "")
                for item in application.findall("meta-data")}
    maps_key = metadata.get("com.google.android.geo.API_KEY", "")
    if not maps_key or "MISSING" in maps_key or "${" in maps_key:
        fail("Google Maps key is missing from the packaged application.")
    return {"package": manifest.get("package"), "version": version,
            "build_number": int(build_number),
            "target_sdk": int(sdk.get(ANDROID_NS + "targetSdkVersion")),
            "debuggable": False, "maps_key_present": True}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--api-url", default=os.environ.get("API_BASE_URL", ""))
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--check-only", action="store_true")
    mode.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    validate_inputs(args.version, args.build_number, args.api_url)
    flutter = json.loads(capture(["flutter", "--version", "--machine"]))
    if flutter["frameworkVersion"] != FLUTTER_VERSION:
        fail(f"Use Flutter {FLUTTER_VERSION} for this release pipeline.")
    signature()
    if args.check_only:
        print("Release inputs, pinned Flutter and private upload key are valid.")
        return
    if not args.verify_only:
        subprocess.run(["flutter", "pub", "get", "--enforce-lockfile"], cwd=ROOT, check=True)
        subprocess.run([
            "flutter", "build", "appbundle", "--release", "--no-pub",
            f"--build-name={args.version}", f"--build-number={args.build_number}",
            "--dart-define=CHETIWA_ENV=production",
            f"--dart-define=CHETIWA_API_BASE_URL={args.api_url}",
            "--dart-define=CHETIWA_ALLOW_DIRECT_PROVIDER_FALLBACK=false",
        ], cwd=ROOT, check=True)
    fingerprint = signature(BUNDLE)
    tool = bundletool()
    capture(tool + ["validate", f"--bundle={BUNDLE}"])
    xml = capture(tool + ["dump", "manifest", f"--bundle={BUNDLE}", "--module=base"])
    report = validate_manifest(xml, args.version, args.build_number)
    report.update({"flutter_version": flutter["frameworkVersion"],
                   "bundletool_version": BUNDLETOOL_VERSION,
                   "verification_scope": "bundle structure, manifest, payload signature",
                   "build_invoked_by_this_run": not args.verify_only,
                   "upload_certificate_sha256": fingerprint,
                   "aab_sha256": hashlib.sha256(BUNDLE.read_bytes()).hexdigest(),
                   "aab_bytes": BUNDLE.stat().st_size,
                   "source_commit": capture(["git", "rev-parse", "HEAD"]),
                   "source_has_local_changes": bool(capture(["git", "status", "--porcelain"])),
                   "signature_verified_for_every_payload": True})
    report_path = BUNDLE.with_name("release-verification.json")
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))
    print(f"Verified artifact: {BUNDLE}\nVerification report: {report_path}")


if __name__ == "__main__":
    main()
