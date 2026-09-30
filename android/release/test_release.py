import importlib.util
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest
import zipfile


HERE = Path(__file__).resolve().parent
SPEC = importlib.util.spec_from_file_location("release_build", HERE / "build.py")
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class ReleaseInputsTest(unittest.TestCase):
    def test_public_origin(self):
        release.validate_inputs("1.0.0", "7", "https://chetiwa-api.ezplatforms.com")

    def test_invalid_inputs_are_rejected(self):
        cases = [
            ("1.0", "7", "https://example.com"),
            ("1.0.0", "0", "https://example.com"),
            ("1.0.0", "2100000001", "https://example.com"),
            ("1.0.0", "7", "http://example.com"),
            ("1.0.0", "7", "https://127.0.0.1"),
            ("1.0.0", "7", "https://localhost"),
            ("1.0.0", "7", "https://test.local"),
            ("1.0.0", "7", "https://user:password@example.com"),
            ("1.0.0", "7", "https://example.com/path"),
            ("1.0.0", "7", "https://example.com?key=private"),
            ("1.0.0", "7", "https://example.com:invalid"),
        ]
        for args in cases:
            with self.subTest(args=args), self.assertRaises(SystemExit):
                release.validate_inputs(*args)

    def manifest(self, target="36", debuggable="false", maps="fixture-key", version="1.0.0"):
        return f'''<manifest xmlns:android="http://schemas.android.com/apk/res/android"
          package="com.ezplatforms.chetiwa" android:versionName="{version}" android:versionCode="7">
          <uses-sdk android:minSdkVersion="24" android:targetSdkVersion="{target}"/>
          <application android:debuggable="{debuggable}">
            <meta-data android:name="com.google.android.geo.API_KEY" android:value="{maps}"/>
          </application></manifest>'''

    def test_packaged_manifest(self):
        report = release.validate_manifest(self.manifest(), "1.0.0", "7")
        self.assertEqual(report["target_sdk"], 36)
        self.assertNotIn("fixture-key", str(report))

    def test_bad_packaged_manifest(self):
        for change in [{"target": "35"}, {"debuggable": "true"}, {"maps": ""},
                       {"maps": "MISSING_MAPS_KEY"}, {"version": "0.9.0"}]:
            with self.subTest(change=change), self.assertRaises(SystemExit):
                release.validate_manifest(self.manifest(**change), "1.0.0", "7")


@unittest.skipUnless(all(shutil.which(tool) for tool in ("java", "keytool", "jarsigner")),
                     "A JDK is required for signature verification fixtures")
class UploadSignatureTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="chetiwa-signature-test-")
        cls.root = Path(cls.temporary.name)
        (cls.root / "app").mkdir()
        for alias in ["expected", "other", "debug"]:
            name = "Android Debug" if alias == "debug" else "Chetiwa disposable test fixture"
            cls.run_tool(["keytool", "-genkeypair", "-keystore", str(cls.root / f"{alias}.p12"),
                          "-storetype", "PKCS12", "-alias", alias, "-storepass", "fixture-password",
                          "-keypass", "fixture-password", "-keyalg", "RSA", "-keysize", "2048",
                          "-validity", "2", "-dname", f"CN={name}"])
        cls.properties = cls.root / "key.properties"
        cls.properties.write_text("storeFile=../expected.p12\nstorePassword=fixture-password\n"
                                  "keyPassword=fixture-password\nkeyAlias=expected\n")

    @classmethod
    def tearDownClass(cls):
        cls.temporary.cleanup()

    @staticmethod
    def run_tool(command):
        result = subprocess.run(command, text=True, capture_output=True)
        if result.returncode:
            raise AssertionError(f"Fixture command failed: {command[0]} (exit {result.returncode})")
        return result

    def create_bundle(self, name, signer=None):
        path = self.root / f"{name}.aab"
        with zipfile.ZipFile(path, "w") as archive:
            archive.writestr("base/manifest/AndroidManifest.xml", b"manifest fixture")
            archive.writestr("base/dex/classes.dex", b"dex fixture")
        if signer:
            self.run_tool(["jarsigner", "-keystore", str(self.root / f"{signer}.p12"),
                           "-storepass", "fixture-password", str(path), signer])
        return path

    def verify(self, bundle=None, properties=None):
        command = ["java", str(HERE / "VerifyUploadSignature.java"), str(properties or self.properties)]
        if bundle:
            command.append(str(bundle))
        return subprocess.run(command, text=True, capture_output=True)

    def test_valid_upload_key_and_signed_payload(self):
        result = self.verify(self.create_bundle("valid", "expected"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertRegex(result.stdout.strip(), r"^[0-9a-f]{64}$")

    def test_unsigned_payload_rejected(self):
        self.assertNotEqual(self.verify(self.create_bundle("unsigned")).returncode, 0)

    def test_other_certificate_rejected(self):
        self.assertNotEqual(self.verify(self.create_bundle("wrong", "other")).returncode, 0)

    def test_added_unsigned_payload_rejected(self):
        path = self.create_bundle("partial", "expected")
        with zipfile.ZipFile(path, "a") as archive:
            archive.writestr("base/assets/injected.txt", b"unsigned data")
        self.assertNotEqual(self.verify(path).returncode, 0)

    def test_tampered_payload_rejected(self):
        signed = self.create_bundle("original", "expected")
        tampered = self.root / "tampered.aab"
        with zipfile.ZipFile(signed) as source, zipfile.ZipFile(tampered, "w") as destination:
            for item in source.infolist():
                data = b"modified dex" if item.filename == "base/dex/classes.dex" else source.read(item)
                destination.writestr(item, data)
        self.assertNotEqual(self.verify(tampered).returncode, 0)

    def test_debug_upload_key_rejected(self):
        properties = self.root / "debug.properties"
        properties.write_text("storeFile=../debug.p12\nstorePassword=fixture-password\n"
                              "keyPassword=fixture-password\nkeyAlias=debug\n")
        self.assertNotEqual(self.verify(properties=properties).returncode, 0)

    def test_missing_key_does_not_disclose_private_config(self):
        properties = self.root / "missing.properties"
        properties.write_text("storeFile=../private-path.p12\nstorePassword=private-password\n"
                              "keyPassword=private-key-password\nkeyAlias=private-alias\n")
        result = self.verify(properties=properties)
        self.assertNotEqual(result.returncode, 0)
        for private in ["private-path", "private-password", "private-key-password", "private-alias"]:
            self.assertNotIn(private, result.stdout + result.stderr)


if __name__ == "__main__":
    unittest.main()
