from pathlib import Path

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
    block = marker + '\n    ' + '\n    '.join(permissions)
    text = text.replace(marker, block, 1)
manifest.write_text(text, encoding='utf-8')

print('Android permissions configured successfully.')
