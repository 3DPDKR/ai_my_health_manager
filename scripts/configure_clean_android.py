from pathlib import Path
import struct
import zlib

manifest = Path('clean_app/android/app/src/main/AndroidManifest.xml')
text = manifest.read_text(encoding='utf-8')
permissions = [
    '<uses-permission android:name="android.permission.INTERNET"/>',
    '<uses-permission android:name="android.permission.ACCESS_NETWORK_STATE"/>',
    '<uses-permission android:name="android.permission.CAMERA"/>',
    '<uses-permission android:name="android.permission.RECORD_AUDIO"/>',
    '<uses-permission android:name="android.permission.READ_MEDIA_IMAGES"/>',
]
if 'android.permission.INTERNET' not in text:
    marker = '<manifest xmlns:android="http://schemas.android.com/apk/res/android">'
    text = text.replace(marker, marker + '\n    ' + '\n    '.join(permissions), 1)
text = text.replace('android:label="ai_health_assistant"', 'android:label="AI 건강비서"')
manifest.write_text(text, encoding='utf-8')

# flutter_local_notifications 19.x requires Android core library desugaring.
# flutter create currently generates Kotlin DSL (build.gradle.kts), but keep
# Groovy support as a fallback so future Flutter template changes do not break CI.
kts = Path('clean_app/android/app/build.gradle.kts')
if kts.exists():
    gradle = kts.read_text(encoding='utf-8')
    if 'isCoreLibraryDesugaringEnabled = true' not in gradle:
        compile_marker = 'compileOptions {'
        gradle = gradle.replace(
            compile_marker,
            compile_marker + '\n        isCoreLibraryDesugaringEnabled = true',
            1,
        )
    if 'coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:' not in gradle:
        dependency_block = '''\n\ndependencies {\n    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")\n}\n'''
        gradle = gradle.rstrip() + dependency_block
    kts.write_text(gradle, encoding='utf-8')
else:
    groovy = Path('clean_app/android/app/build.gradle')
    if not groovy.exists():
        raise FileNotFoundError('Android app Gradle file was not generated.')
    gradle = groovy.read_text(encoding='utf-8')
    if 'coreLibraryDesugaringEnabled true' not in gradle:
        compile_marker = 'compileOptions {'
        gradle = gradle.replace(
            compile_marker,
            compile_marker + '\n        coreLibraryDesugaringEnabled true',
            1,
        )
    if "coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:" not in gradle:
        dependency_block = '''\n\ndependencies {\n    coreLibraryDesugaring 'com.android.tools:desugar_jdk_libs:2.1.5'\n}\n'''
        gradle = gradle.rstrip() + dependency_block
    groovy.write_text(gradle, encoding='utf-8')


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
    create_icon(Path('clean_app/android/app/src/main/res') / folder / 'ic_launcher.png', size)

print('Android permissions, desugaring, app label, and icon configured.')
