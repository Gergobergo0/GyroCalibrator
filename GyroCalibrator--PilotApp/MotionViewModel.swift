//
//  MotionViewModel.swift
//  GyroCalibrator--PilotApp
//
//  Created by Gergo Gelegonya on 2025. 09. 05..
//

import Foundation
import SwiftUI
import UIKit  //haptika

@MainActor
final class MotionViewModel: ObservableObject {
    @Published var yawRad: Double = 0
    @Published var pitchRad: Double = 0
    @Published var rollRad: Double = 0
    @Published var isCalibrated: Bool = false
    
    @Published var countdownRemaining: Int? = nil  //3...0, ha nincs épp stillness: nil
    @Published var stillnessProgress: Double = 0   //0..1 progress bar-hoz
    
    private let service = MotionService()
    private var lastAnnouncedSecond: Int? = nil
    
    private var previousCalibratedState: Bool = false
    
    private var firstTimeCalibrateSwitcher: Bool = false //haptikus jelzeshez mikor eleri a kalibralt allapotot
    
    func start() {
        service.onUpdate = { [weak self] upd in
            guard let self else { return }
            self.yawRad = upd.orientation.yaw
            self.pitchRad = upd.orientation.pitch
            self.rollRad = upd.orientation.roll
            self.isCalibrated = upd.orientation.isCalibrated
            
            //stillness visszaszamlalas
            if previousCalibratedState && !self.isCalibrated {
                firstTimeCalibrateSwitcher = false
                let generator = UINotificationFeedbackGenerator()
                for i in 0..<3 {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.15) {
                        generator.notificationOccurred(.error) //vagy .error
                    }
                }
            }
            previousCalibratedState = self.isCalibrated
            let need = max(0.001, upd.requiredSeconds)
            //print("[GUI] countDownReaming: \(countdownRemaining)")
            //print("self.isCalibrated: \(self.isCalibrated)  -   previousCalibratedState: \(previousCalibratedState)")

            if !self.isCalibrated {
                self.stillnessProgress = min(1.0, upd.stillnessSeconds / need)
                firstTimeCalibrateSwitcher = false
                
                let remaining = max(0.0, need - upd.stillnessSeconds)
                
                if remaining > 0 {
                    let rInt = Int(ceil(remaining))
                    self.countdownRemaining = rInt
                    
                    //haptika minden egész másodpercnél, ha változott
                    if self.lastAnnouncedSecond != rInt {
                        self.lastAnnouncedSecond = rInt
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    }
                }
            } else {
                
                
                if firstTimeCalibrateSwitcher == false {
                    firstTimeCalibrateSwitcher = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)

                }
                self.countdownRemaining = nil
                self.lastAnnouncedSecond = nil
            }
        }
        
        service.start()
    }
    
    func stop() {
        service.stop()
        countdownRemaining = nil
        stillnessProgress = 0
        lastAnnouncedSecond = nil
    }
    
    func calibrateNow() {
        service.calibrateNow()
    }
    
    //megjelenites fokban
    var yawDeg: Double { yawRad * 180.0 / .pi }
    var pitchDeg: Double { pitchRad * 180.0 / .pi }
    var rollDeg: Double { rollRad * 180.0 / .pi }
    
}
