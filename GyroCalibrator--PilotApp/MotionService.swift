//
//  MotionService.swift
//  GyroCalibrator--PilotApp
//
//  Created by Gergo Gelegonya on 2025. 09. 05..
//

//

import CoreMotion //mozgas es szenzoradatok
import simd //vektorok, quaternionok
import QuartzCore //idomeres

//TODO: atgondolni melyiket hogyan kell hasznalni
/*
 problema: relativ irany, abszoulit irany, melyik elerheto, mi legyen a 0,0,0?
 otletek:
 
 
 ------------------------------------------------------------------------------------------------------------------------------
 .xTrueNorthZVertical, XMagneticNorthZVertical (pontatlanabb):
  - Z tengely mindig a gracitacioval parguzamos - fuggolegesen felfele mutat
  - X tengely mindig a valodi eszak fele mutat Core Location + magnetometer alapjan korrigalva
  - Y tengely ketto keresztszorzata, tehat kelet fele mutat
  - Yaw = 0 -> a keszulek X tengelye eszak fele mutat
  - Yaw > 0 -> kelet fele fordulok (jobbra)
  - Yaw < 0 -> Nyugat fele fordulok (balra)
 
  - Pitch = 0 -> a device kijelzoje vizszintesen all, parhuzamos a talajjal
  - Pitch > 0 -> felfele bolint, a teteje emelkedik
  - Pitch < 0 -> lefele bolint, a teteje sullyed
 
  - Roll = 0 a keszulek kijelzoje vizszintesen van, nem dol oldalra
  - Roll > 0 -> jobbra dol
  - Roll < 0 -> balra dol
  (0,0,0) Amikor a telefon kijelzoje vizszintesen van, a teteje eszak fele mutat, nincs oldalra dolve
 
 .xArbitraryZVertical:
  - Z tengely mindig a gravitacioval parhuzamos (fuggolegesen felfele)
  - X tengely az inditas pillanataban dol el
  - Y tengely Z es X keresztszorzata hogy ortogonalis legyen
 
  - Yaw = 0 -> a device X tengelye arra mutat amerra az inditas pillanataban volt
  - Yaw > 0 -> az inditaskori iranyhoz kepest jobbra
  - Yaw < 0 -> az inditaskori iranyhoz kepest balra
 
  - Pitch = 0 -> A keszulek kijelzoje vizszintesen van, parhuzamos a talajjal
  - Pitch > 0 -> felfele bolint, teteje emelkedik
  - Pitch < 0 -> lefele bolint, a teteje sullyed
 
  - Roll = 0 -> device kijelzoje vizszintesen van, nem dol oldalra
  - Roll > 0 -> jobbra dol\
  - Roll < 0 -> balra dol
 (0,0,0), amikor a keszulek kijelzoje vizszintes, a teteje arra mutat amerre az inditas pillanataban volt, nincs oldalra dolve
 ------------------------------------------------------------------------------------------------------------------------------

 Otletek:
 - Elso OCR utan egy relativ meres, mert akkor mar tudjuk h kb arra nez
 */


final class MotionService {
    
    enum CalibState {
        case notCalibrated
        case calibrated
    }
    
    struct Orientation {
        var pitch : Double //euler szogek radianban
        var roll: Double
        var yaw: Double
        var timeStamp : TimeInterval
        var isCalibrated: Bool
    }
    
  
    
    var onUpdate: ((Update) -> Void)? //guihoz callback
    
    private let motion = CMMotionManager() //mozgas-szenzoradatok
    private let queue = OperationQueue() //hatterszalhoz
    private let lock = NSLock() //thread safe iras-olvasas

    
    //legutobbi minta
    private var _latest: Orientation?
    var latest: Orientation? { //thread-safe getter
        lock.lock()
        defer {lock.unlock()}
        return _latest
    }
    
    
    private var lastQuat : simd_quatd? //legutobbi mintaveteli eredmeny (= jelenlegi orientacio)
    private var referenceQuat : simd_quatd? //kalibracio eredmenye
    private var stillnessStart: TimeInterval? //mozdulatlansag kezdete
    private var lastAutoCalibTime: TimeInterval = 0 //utolso kalibracio ideje
    
    
    
    var gyroThresholdToCalibrateRadPerSec : Double = 0.2 //giroszkop a mozdulatlansaghoz
    var accelThresholdToCalibrateMS2 : Double = 0.3 //gyorsulasmero a mozdulatlansahgoz
    var stillnessRequiredSeconds: Double = 3.0 //ennyi masodperc nyugalom kell a kalibraciohoz
    //var autoCalibCooldownSeconds: Double = 2.0 //ket autokalibracio kozott ennyi ido teljesn el
    
    var gyroThresholdToShakeRadPerSec: Double = 6.0 //giroszkop shake haterertek
    var accelThresholdToShake : Double = 7.0 //gyorsulasmero haterertek acceleration
    var twoShakesSecond : Double = 1.0 //mennyi ido teljen el ket mozdulat kozott hogy hogy azt szamoljuk
    var shakeToCalibrate: Int = 10 //hany mozdulat egy razas

    private(set) var state: CalibState = .notCalibrated //kivulrol olvashato, bdlulrol allithato
    
    private var shakeCount : Int = 0 //counter shakehez (shakeCount...shakeToCalibrate)
    private var lastShakedTime : TimeInterval = 0
    
    
    
    
    
    
    //kezi kalibracio
    func calibrateNow() {
        print("[] Manual Calibrate Now []")
        /*
        lock.lock() //zarolas ha van friss quaternion
        if let current = lastQuat {
            enterCalibrated(with: current, now: CACurrentMediaTime())
        }
        lock.unlock()
          */
        var snapshot: simd_quatd?
        lock.lock()
        snapshot = lastQuat
        lock.unlock()
        if let current = snapshot {
            enterCalibrated(with: current, now: CACurrentMediaTime())
        }
         

    }
    
    
    private var lastDeviceMotionQuat: simd_quatd? //csak calibrate allapotban nem nil
    //kezi referencia torlo
    public func calibrateOff() {
        print("CalibrateOff()")
        enterNotCalibrated()
    }
    
    public func isCalibrated()->Bool {
        return (state == .calibrated)
    }
    
    func start(updateInterval: TimeInterval = 0.02) {
        guard motion.isDeviceMotionAvailable else {return}
        
        motion.deviceMotionUpdateInterval = updateInterval //mintaveteli frekvencia
        
        //let avialable = CMMotionManager.availableAttitudeReferenceFrames()
        
        let frame = CMAttitudeReferenceFrame.xArbitraryZVertical
        
        motion.startDeviceMotionUpdates(using: frame, to: queue) { [weak self] data, _ in //elinditja a folyamatos frissitest a haterben
            //data a CoreMotion CMDeviceMotion tipusu adatcsomag a szenzorok allapotat tartalmazza
            guard let self, let dm = data else { return }
            
            //dm a coremotion CMDevice objektum,
            let q = Self.quat(from: dm.attitude.quaternion)
            self.lastDeviceMotionQuat = q //quaternion
            self.lastQuat = q
            
            //mozdulatlansag detektalasa
            //szogsebesseg vektor
            let gyro = dm.rotationRate // rad/s
            //eukliodeszi norma
            let gyroNorm = sqrt(gyro.x*gyro.x + gyro.y*gyro.y + gyro.z*gyro.z)
            
            //gyorsulas
            let ua = dm.userAcceleration // m/s^2
            //euklideszi norma
            let accelNorm = sqrt(ua.x*ua.x + ua.y*ua.y + ua.z*ua.z)
            
            let isStill = (gyroNorm < self.gyroThresholdToCalibrateRadPerSec) && (accelNorm < self.accelThresholdToCalibrateMS2) //akkor van nyugalom ha mindket norma a kuszob alatt van
           
            let isShaked = (gyroNorm > self.gyroThresholdToShakeRadPerSec) || (accelNorm > self.accelThresholdToShake)
            
            let now = CACurrentMediaTime()

            switch self.state {
            case .notCalibrated:
                if isStill {
                    if self.stillnessStart == nil
                    {
                        self.stillnessStart = now
                    }
                    
                    self.updateStillness(now: now) //frissiti a stillnesst
                    
                    if let s0 = self.stillnessStart { //ha eleg ideje mozdulatlan beallitja a kalibraciot
                        if (now - s0) >= self.stillnessRequiredSeconds {
                            self.enterCalibrated(with: q, now: now)
                        }
                    }
                } else {
                    self.resetStillness() //ha nincs nyugalom visszaallitja a stillness merot
                }
                
                //self.resetShakeIfTooOld(now: now) //notCalibrated allapotban a razas nem szamit
                
            case .calibrated:
                if isShaked { //ha razas van
                    self.processShake(now: now)
                } else { //
                    self.resetShakeIfTooOld(now: now)
                }
            
                //calibrated allapotban a nyugalmat csak UI-ban kell merni
                if isStill {
                    if self.stillnessStart == nil { self.stillnessStart = now }
                    self.updateStillness(now: now)
                } else {
                    self.resetStillness()
                }
            }
            
            
            
            
            
            /*
             var relQuat: simd_quatd //relativ elmozdulas
             //ha van referencia-quaternion kiszamilja a forgatast
             if let reference = self.referenceQuat {
             relQuat = reference.inverse * q //az inverze visszaforgatja a koordinatarendszert a referenciaallapotbol az "alapba"
             } else { //ha nincs az aktualist hasznaljuk
             relQuat = q
             }*/
            

            
            //--------------------GUI--------------------
            let relQuat: simd_quatd = {
                if self.state == .calibrated, let ref = self.referenceQuat {
                    return ref.inverse * q //az inverze visszaforgatja a koordinatarendszert a referenciaallapotbol az "alapba" 0,0,0
                } else {
                    return q
                }
            }()
            
            let (yaw, pitch, roll) = Self.toEulerAngles(from: relQuat)
            
            //mintacsomag osszeallitasa a guinak
            let sample = Orientation(
                pitch: pitch,
                roll: roll,
                yaw: yaw,
                timeStamp: now,
                isCalibrated: (self.state == .calibrated)
            )
            
            self.lock.lock()
            self._latest = sample
            let still = self._stillnessSeconds
            let needed = self.stillnessRequiredSeconds
            self.lock.unlock()
            
            //GUI callback a fő szálra
            if let cb = self.onUpdate {
                DispatchQueue.main.async {
                    cb(Update(orientation: sample, stillnessSeconds: still, requiredSeconds: needed))
                }
            }
            //--------------------GUI--------------------//

        }
    }
    
    //MARK: allapotvaltozasok
    private func enterCalibrated(with q: simd_quatd, now: TimeInterval) {
        print("enterCalibrated()")
        lock.lock()
        state = .calibrated
        referenceQuat = q
        shakeCount = 0
        lastShakedTime = now
        //resetStillness()
        resetStillnessLocked()

        lock.unlock()
    }
    
    private func enterNotCalibrated() {
        print("enterNotCalibrated()")
        lock.lock()
        state = .notCalibrated
        referenceQuat = nil
        shakeCount = 0
        lastShakedTime = 0
        //resetStillness()
        resetStillnessLocked()
        lock.unlock()
    }
    
    
    //
    private func resetShakeIfTooOld(now: TimeInterval) {
        if lastShakedTime > 0, (now - lastShakedTime) > twoShakesSecond { //ha tul reg volt az utolso razas nullazza a szamlalot
            shakeCount = 0
        }
    }


    

    
    //miota van nyugalomban a telefon
    private func updateStillness(now: TimeInterval) {
        guard let s0 = stillnessStart else {return}
        lock.lock(); _stillnessSeconds = now - s0; lock.unlock()
    }
    
    //nullazza a nyugalmat
    private func resetStillnessLocked() {
        stillnessStart = nil
        _stillnessSeconds = 0
    }
    
    
    private func resetStillness() {
        lock.lock()
        //stillnessStart = nil
        //_stillnessSeconds = 0
        resetStillnessLocked()
        lock.unlock()
    }
    
    private func processShake(now: TimeInterval) {
        
        print("Shaked: \(shakeCount)/\(shakeToCalibrate)")
        if lastShakedTime > 0, (now - lastShakedTime) > twoShakesSecond { //ha a razasok kozti ido nagyobb a kuszobnel
            shakeCount = 1
        } else {
            shakeCount += 1 //ha ket razas kozti ido < twoShakesSecond
        }
        lastShakedTime = now
        
        if shakeCount >= shakeToCalibrate {
            enterNotCalibrated()
        }
    }
    
    //leallitja a szenzort es torli az allapotokat
    func stop() {
        motion.stopDeviceMotionUpdates()
        lock.lock()
        stillnessStart = nil
        lastDeviceMotionQuat = nil
        lock.unlock()
    }
    
    //---------------------------------------------------------------------------
    //MARK: GUIHOZ
    struct Update {
        let orientation: Orientation
        let stillnessSeconds: Double
        let requiredSeconds: Double
    }
    

    //olvasható stillness (thread-safe getter)
    private var _stillnessSeconds: Double = 0
    var stillnessSeconds: Double {
        lock.lock(); defer { lock.unlock() }
        return _stillnessSeconds
    }

    
    //---------------------------------------------------------------------------

    
}

private extension MotionService { //segedfuggveny
    /*
     a simd_quat-ban vannak beepitett fuggvenyek amikkel jobb dolgozni
     */
    static func quat(from cmq: CMQuaternion) -> simd_quatd {
        
        return simd_quatd(ix: cmq.x, iy: cmq.y, iz: cmq.z, r: cmq.w) //tipuskonverzio Apple quaternion -> simd_quatd
    }
    
    /*
     Euler szogekke alakitas
     https://en.wikipedia.org/wiki/Conversion_between_quaternions_and_Euler_angles
     */
    static func toEulerAngles(from q: simd_quatd) -> (yaw: Double, pitch: Double, roll: Double) {
        let x = q.imag.x, y = q.imag.y, z = q.imag.z, w = q.real
        
        //yaw (Z)
        let siny_cosp = 2.0 * (w*z + x*y)
        let cosy_cosp = 1.0 - 2.0 * (y*y + z*z)
        let yaw = atan2(siny_cosp, cosy_cosp)
        
        //pitch (Y)
        var sinp = 2.0 * (w*y - z*x)
        //levagjuk a felso-also hatart -1 es 1 koze
        sinp = max(-1.0, min(1.0, sinp))
        let pitch = asin(sinp)
        
        //roll (X)
        let sinr_cosp = 2.0 * (w*x + y*z)
        let cosr_cosp = 1.0 - 2.0 * (x*x + y*y)
        let roll = atan2(sinr_cosp, cosr_cosp)
        
        return (yaw, pitch, roll)
         



    }

    
}


/*
import CoreMotion

final class MotionService {
    private let motion = CMMotionManager()
    private let queue = OperationQueue() //kulon szal a mozgasadatok frissulesehez
    private let lock = NSLock() //sima lock az adatok irasahoz, olvasasahoz ket szal kozott

    struct Orientation { ///yaw pitch roll ertekek radianban!!!
        var pitch: Double //elore-hatra billenes
        var roll: Double //oldalra doles
        var yaw: Double //korbefordulas a fuggole ges tengely korul
        var timestamp: TimeInterval
    }

    private var _latest: Orientation? //utolso mert allapot
    var latest: Orientation? { //publikus getter
        lock.lock() //zarolja az eroforrast
        defer { lock.unlock() } //mikor a scope vegeter elengedi a lockot
        return _latest
    }
    
    //elinditja az erzekelest -- updateInterval: milyen gakran frissitse az adatot
    func start(updateInterval: TimeInterval = 0.02) {
        guard motion.isDeviceMotionAvailable else { return } //ellenorzi h az eszkoz tamogatja-e a deviceMotiont
        motion.deviceMotionUpdateInterval = updateInterval //frissites gyakorisaganak beallitasa
        
        let available = CMMotionManager.availableAttitudeReferenceFrames()
        let frame: CMAttitudeReferenceFrame
        
        if available.contains(.xTrueNorthZVertical) {
            frame = .xTrueNorthZVertical /*Z tengely a gravitacioval parhuzamos, X valodi eszak fele, yaw eszaktol mert irany*/ // ehhez szukseg van a Core Location GPS, magneses adatokra - helyhozzaferes
        } else if available.contains(.xMagneticNorthZVertical) {
            frame = .xMagneticNorthZVertical // - magneses eszakhoz kepest
        } else {
            frame = .xArbitraryZVertical //relativ
        }
        motion.startDeviceMotionUpdates/*elinditja a folyamatos frissitest*/(using: frame , to: queue/*a frissitesek kulon queue-n futnak*/) { [weak self/*memory leak ellen*/] data, _ in
            //.xMagneticNorthZVertical - magneses eszakhoz kepest
            //.xArbitraryCorrectedZVertical - relativ
            
            //TODO: ha fekvo allapotban van a device akkor mashogy kell ertelmezni az adatokat (szukseges-e?)
            guard let self, let att = data?.attitude else { return } //ellenorzi felszabadult-e az objektum
            let sample = Orientation(
                pitch: att.pitch,
                roll: att.roll,
                yaw: att.yaw,
                timestamp: CACurrentMediaTime()
            )
            self.lock.lock()
            self._latest = sample //eltarolja a az adatokat
            self.lock.unlock()
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
    }
}
*/

