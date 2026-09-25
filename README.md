# SAT-LINK: Deep Space Array 🛰️

> SAT-LINK is a tactical radio operator simulation. Players track celestial anomalies using azimuth, elevation, and frequency to intercept secure payloads. Featuring a cyberpunk UI with real-time spectrums, you must decrypt signals, manage system heat, and evade active enemy traces to earn Intel Credits and upgrade your hardware.

![SAT-LINK Screenshot](https://via.placeholder.com/800x450.png?text=Insert+Main+Gameplay+Screenshot+Here)

## 📡 Features

* **Immersive Cyberpunk UI:** Custom-drawn, hardware-accelerated interface built entirely without standard OS controls.
* **5 Real-Time Visualization Engines:** 
  * Tactical Red Waterfall
  * Cold Blue SDR Matrix
  * Real-time Oscilloscope (CRT Phosphor style)
  * FFT Spectrum Analyzer
  * Digital Seismometer
* **Dynamic Physics & Telemetry:** Manage Azimuth and Elevation mechanics while preventing your antenna motor from overheating (`SYSTEM OVERHEAT`).
* **Active Enemy Trace (Minigame):** Decrypt intercepted hexadecimal payloads under pressure before a proxy firewall tracks your location and triggers a system lockdown.
* **Engineering Terminal (Upgrades):** Spend earned Intel Credits on hardware upgrades (Wide-Band Dish, Cryogenic Motor, Digital Auto-Tuner) managed via a local database.
* **Procedural Audio:** Integrated BASS Audio library generating real-time sine waves based on Signal-to-Noise Ratio (SNR) blended with immersive ambient radio static.

## 🛠️ Tech Stack

This project is built as a lightweight, native desktop application using:
* **[Lazarus IDE / Free Pascal (FPC)](https://www.lazarus-ide.org/):** Core engine and application framework.
* **[BGRABitmap](https://github.com/bgrabitmap/bgrabitmap):** Used for advanced 2D rendering, antialiasing, and custom control drawing (Sliders, Radar, Waterfalls).
* **[BASS Audio Library](http://www.un4seen.com/):** For real-time procedural audio generation and hardware-level sound control.
* **SQLite3:** Embedded database handling dynamic celestial targets, player wallets, upgrade scaling, and transmission logs.

## 🚀 Getting Started

### Prerequisites
1. **Lazarus IDE** (v2.2.6 or higher recommended).
2. **BGRABitmap** package installed via Online Package Manager (OPM) in Lazarus.
3. Windows/Linux environment.

