# Polar Travel (v2)

Open-source street, satellite, and turn-by-turn navigation app styled in **Royal Blue, Powder Blue, Silver, and White** with a custom **Polar Bear Map Pin** logo.

## What's New in v2
- **Satellite / Hybrid / Street Switcher:** Toggle between OpenStreetMap streets, Esri World Imagery satellite tiles, and Hybrid (Satellite + crisp street labels).
- **OpenStreetMap Road Feature Overlays (`lib/overpass_service.dart`):** Toggle & scan for **Stop Signs**, **Traffic Lights**, **School Zones** (with shaded radius circles), **Fixed Speed Cameras**, and **Construction Zones**.
- **Waze-Style Quick Road Reports:** Tap the alert button to drop persistent pins for **Speed Traps**, **Road Closures**, **Construction**, or **Heavy Traffic**.
- **Optional Live Rush-Hour Traffic Flow:** Paste a free TomTom API key in the Layers sheet to overlay live red/amber/green slow-traffic tiles.
- **Voice-Guided Turn-by-Turn Navigation (`lib/voices_screen.dart`):** Built-in Navigation Voices screen (*Arctic Clear*, *Boreal Calm*, *Aurora*, *Tundra Crisp*) with live audio previews, spoken street names toggle, and speech speed slider.

## Build Your APK in the Cloud (No Local Setup Required)
1. Create a free repository on GitHub (e.g., `polar-travel`).
2. Extract this ZIP and upload all files (including `.github/workflows/build_apk.yml`) to the `main` branch.
3. Open the **Actions** tab -> **Build Polar Travel APK**.
4. Download **`PolarTravel-APK`** from the **Artifacts** section, unzip it, and install `PolarTravel-release.apk` on your Android phone.
