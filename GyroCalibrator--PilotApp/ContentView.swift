import SwiftUI
import UIKit
struct ContentView: View {
    @StateObject private var vm = MotionViewModel()

    var body: some View {
        VStack(spacing: 20) {
            //kalib statusz
            HStack(spacing: 8) {
                Circle()
                    .fill(vm.isCalibrated ? Color.green : Color.gray)
                    .frame(width: 12, height: 12)
                Text(vm.isCalibrated ? "Calibrated" : "Not calibrated")
                    .font(.headline)
            }
            .padding(10)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())

            //visszaszamlalas
            VStack(spacing: 8) {
                if let remain = vm.countdownRemaining {
                    Text(remain > 0 ? "Hold still…" : "Calibrated!")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Text("\(remain == 0 ? 5 : remain)")
                        .font(.system(size: 56, weight: .bold, design: .rounded))
                        .monospacedDigit()
                } else {
                    Text("Move or hold still to start calibration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                ProgressView(value: vm.stillnessProgress)
                    .progressViewStyle(.linear)
                    .frame(maxWidth: 320)
            }
            .padding(.vertical, 8)

            
            VStack(alignment: .leading, spacing: 10) {
                valueRow(label: "Yaw", rad: vm.yawRad, deg: vm.yawDeg)
                valueRow(label: "Pitch", rad: vm.pitchRad, deg: vm.pitchDeg)
                valueRow(label: "Roll", rad: vm.rollRad, deg: vm.rollDeg)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.secondarySystemBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            //gombok
            HStack {
                Button(action: { vm.start() }) {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(action: { vm.stop() }) {
                    Label("Stop", systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)

                Spacer()

                Button(action: {
                    vm.calibrateNow()
                    let generator = UINotificationFeedbackGenerator()

                    generator.notificationOccurred(.success)
                }) {
                    Label("Set zero", systemImage: "scope")
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
        .onAppear { vm.start() }
        .onDisappear { vm.stop() }
    }

    @ViewBuilder
    private func valueRow(label: String, rad: Double, deg: Double) -> some View {
        HStack {
            Text(label)
                .font(.headline)
                .frame(width: 60, alignment: .leading)
            Spacer()
            Text(String(format: "%.3f rad", rad))
                .monospacedDigit()
            Text("•")
                .foregroundStyle(.secondary)
            Text(String(format: "%.1f°", deg))
                .monospacedDigit()
        }
        .font(.system(.body, design: .rounded))
    }
}
