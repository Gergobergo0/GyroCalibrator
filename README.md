# GyroCalibrator–PilotApp

A SwiftUI iOS pilot app that reads the device’s orientation (yaw/pitch/roll) using CoreMotion.
Includes calibration logic (stillness-based auto-calibration + "shake to de-calibrate") and haptic feedback for user interaction.

## Table of Contents
- [Features](#features)
- [Architecture](#architecture)
- [Requirements](#requirements)
- [Installation & Run](#installation--run)



---

## Features
- **Real-time orientation**: yaw, pitch, roll (in radians), converted from `simd_quatd` -> Euler.
- **Calibration**:
  - Automatic calibration after a set stillness period.
  - Manual calibration (`calibrateNow()`).
  - "Shake to de-calibrate": strong shaking resets calibration.
- **UI integration**: orientation values, calibration state, countdown, progress bar.
- **Haptic feedback**: success/error notifications and countdown ticks.

## Architecture
- `MotionService.swift`
  - Handles CoreMotion (`CMMotionManager`).
  - Converts quaternion -> Euler angles.
  - Calibration logic (stillness & shake detection).
  - Thread-safe state (`NSLock`) and GUI callback (`onUpdate`).
- `MotionViewModel.swift`
  - `@MainActor` SwiftUI ViewModel.
  - Publishes orientation, calibration state, countdown, progress.
  - Triggers haptics on state changes.

## Requirements
- iOS 16+ (recommended), Xcode 15+
- Swift 5.9+
- Frameworks: `CoreMotion`, `simd`, `QuartzCore`, `SwiftUI`, `UIKit` (for haptics)

> Note: `.xArbitraryZVertical` reference frame is used -> **no location permission required**.  
If you switch to `.xTrueNorthZVertical` or `.xMagneticNorthZVertical`, Core Location permissions are needed.

## Installation & Run
1. Open the project in Xcode.
2. Set deployment target to iOS 16+.
3. Run on a physical device (recommended, since sensors are required).
