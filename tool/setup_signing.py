# One-off: creates the release keystore + key.properties, wires signing into Gradle.
import pathlib, secrets, subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
KEYS = pathlib.Path(r"C:\Users\Owner\keys")
JKS = KEYS / "zira-release.jks"

if JKS.exists():
    raise SystemExit("keystore already exists - refusing to overwrite")

pw = secrets.token_urlsafe(18)
subprocess.run(["keytool", "-genkeypair", "-keystore", str(JKS), "-alias", "zira",
                "-keyalg", "RSA", "-keysize", "2048", "-validity", "10950",
                "-storepass", pw, "-keypass", pw, "-dname", "CN=Zira, O=galpartuk, C=IL"],
               check=True, capture_output=True)
(KEYS / "zira-release-credentials.txt").write_text(
    "Zira / tournament manager - release signing\n"
    f"Keystore: {JKS}\nAlias: zira\nStore & key password: {pw}\n"
    "Created: 2026-11-10  Validity: 30 years\n"
    "Keep this file. Losing the keystore means the app can never be updated.\n", encoding="utf-8")
(ROOT / "android" / "key.properties").write_text(
    f"storePassword={pw}\nkeyPassword={pw}\nkeyAlias=zira\nstoreFile={JKS.as_posix()}\n", encoding="utf-8")

p = ROOT / "android" / "app" / "build.gradle.kts"
s = p.read_text(encoding="utf-8")
s = s.replace("plugins {", "import java.util.Properties\nimport java.io.FileInputStream\n\nplugins {", 1)
s = s.replace("android {", """// Release signing lives outside the project tree. See android/key.properties.
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {""", 1)
old = """    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }"""
new = """    signingConfigs {
        create("release") {
            val store = keystoreProperties.getProperty("storeFile")
            if (store != null) {
                storeFile = file(store)
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystoreProperties.getProperty("storeFile") != null) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }"""
assert old in s
s = s.replace(old, new)
s = s.replace("        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).\n", "")
p.write_text(s, encoding="utf-8")
print("ok")
