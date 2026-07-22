from pathlib import Path
import struct
import zlib

APP = Path('clean_app')
ANDROID = APP / 'android'
MANIFEST = ANDROID / 'app/src/main/AndroidManifest.xml'
APP_GRADLE_KTS = ANDROID / 'app/build.gradle.kts'
GRADLE_PROPERTIES = ANDROID / 'gradle.properties'

if not MANIFEST.exists():
    raise FileNotFoundError(f'Missing generated manifest: {MANIFEST}')

manifest = MANIFEST.read_text(encoding='utf-8')
permissions = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>',
    '<uses-permission android:name="android.permission.CAMERA"/>',
    '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
    '<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>',
    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
    '<uses-permission android:name="android.permission.SCHEDULE_EXACT_ALARM"/>',
]
marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
if marker not in manifest:
    raise RuntimeError('Unexpected AndroidManifest.xml format')
for permission in permissions:
    if permission not in manifest:
        manifest = manifest.replace(marker, marker + '\n    ' + permission, 1)
manifest = manifest.replace('android:label="ai_health_assistant"', 'android:label="AI 건강비서"')
MANIFEST.write_text(manifest, encoding='utf-8')

# Write the app Gradle file deterministically instead of patching a generated
# template. This prevents flutter.compileSdkVersion or stale SDK values from
# surviving template changes.
APP_GRADLE_KTS.write_text('''plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.aimyhealthmanager.ai_health_assistant"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.aimyhealthmanager.ai_health_assistant"
        minSdk = 23
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
''', encoding='utf-8')

GRADLE_PROPERTIES.write_text('''org.gradle.jvmargs=-Xmx4G -XX:MaxMetaspaceSize=1G -XX:ReservedCodeCacheSize=512m -XX:+HeapDumpOnOutOfMemoryError
android.useAndroidX=true
android.enableJetifier=true
org.gradle.vfs.watch=false
org.gradle.daemon=false
''', encoding='utf-8')


def chunk(kind, data):
    return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)


def create_icon(path, size):
    pixels = bytearray([241, 250, 243, 255] * size * size)

    def set_pixel(x, y, color):
        if 0 <= x < size and 0 <= y < size:
            i = (y * size + x) * 4
            pixels[i:i + 4] = bytes(color)

    def rect(x0, y0, x1, y1, color):
        for y in range(max(0, y0), min(size, y1)):
            for x in range(max(0, x0), min(size, x1)):
                set_pixel(x, y, color)

    def ellipse(cx, cy, rx, ry, color, angle=0.0):
        import math
        ca, sa = math.cos(angle), math.sin(angle)
        for y in range(int(cy - ry - rx), int(cy + ry + rx) + 1):
            for x in range(int(cx - rx - ry), int(cx + rx + ry) + 1):
                dx, dy = x - cx, y - cy
                px = dx * ca + dy * sa
                py = -dx * sa + dy * ca
                if (px * px) / (rx * rx) + (py * py) / (ry * ry) <= 1:
                    set_pixel(x, y, color)

    dark = (22, 111, 70, 255)
    light = (54, 166, 94, 255)
    margin = int(size * 0.18)
    rect(margin, margin, size - margin, size - margin, (255, 255, 255, 255))
    bar = int(size * 0.18)
    center = size // 2
    rect(center - bar // 2, int(size * 0.27), center + bar // 2, int(size * 0.76), dark)
    rect(int(size * 0.27), center - bar // 2, int(size * 0.76), center + bar // 2, dark)
    ellipse(size * 0.69, size * 0.28, size * 0.12, size * 0.055, light, -0.65)
    ellipse(size * 0.78, size * 0.39, size * 0.105, size * 0.05, dark, 0.55)

    raw = bytearray()
    stride = size * 4
    for y in range(size):
        raw.append(0)
        raw.extend(pixels[y * stride:(y + 1) * stride])
    png = b'\x89PNG\r\n\x1a\n'
    png += chunk(b'IHDR', struct.pack('>IIBBBBB', size, size, 8, 6, 0, 0, 0))
    png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
    png += chunk(b'IEND', b'')
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)


for folder, size in {
    'mipmap-mdpi': 48,
    'mipmap-hdpi': 72,
    'mipmap-xhdpi': 96,
    'mipmap-xxhdpi': 144,
    'mipmap-xxxhdpi': 192,
}.items():
    create_icon(ANDROID / 'app/src/main/res' / folder / 'ic_launcher.png', size)

print('Deterministic Android configuration written: compileSdk=36, targetSdk=36, minSdk=23, Java 17, desugaring enabled.')
