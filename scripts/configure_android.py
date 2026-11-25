import re
from pathlib import Path

manifest_path = Path("android/app/src/main/AndroidManifest.xml")
if not manifest_path.exists():
    raise FileNotFoundError("AndroidManifest.xml not found. Run 'flutter create .' first.")

text = manifest_path.read_text(encoding="utf-8")
text = re.sub(r'android:label="[^"]*"', 'android:label="Polar Travel"', text, count=1)

permissions = [
    '    <uses-permission android:name="android.permission.INTERNET" />',
    '    <uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" />',
    '    <uses-permission android:name="android.permission.ACCESS_COARSE_LOCATION" />',
]
for perm in permissions:
    if perm.strip() not in text:
        text = text.replace("<application", f"{perm}\n    <application", 1)

# Add Android 11+ TTS service query so flutter_tts works reliably
tts_intent = '<action android:name="android.intent.action.TTS_SERVICE" />'
if tts_intent not in text:
    if "<queries>" in text:
        text = text.replace(
            "<queries>",
            "<queries>\n        <intent>\n            <action android:name=\"android.intent.action.TTS_SERVICE\" />\n        </intent>",
            1,
        )
    else:
        queries_block = (
            "    <queries>\n"
            "        <intent>\n"
            "            <action android:name=\"android.intent.action.TTS_SERVICE\" />\n"
            "        </intent>\n"
            "    </queries>\n"
        )
        text = text.replace("</manifest>", f"{queries_block}</manifest>", 1)

manifest_path.write_text(text, encoding="utf-8")
print("Updated AndroidManifest.xml with Polar Travel name, Internet, GPS, and TTS queries.")
