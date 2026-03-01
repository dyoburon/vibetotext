import SwiftUI
import AVFoundation

/// Microphone selection panel (matches the Electron mic settings)
struct MicrophoneSettingsView: View {
    @StateObject private var config = ConfigStore.shared
    @State private var devices: [AudioDevice] = []
    @State private var selectedDeviceID: String = ""
    @State private var statusMessage: String = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Audio Input Device")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)

                    Text("Select the microphone to use for voice recording.")
                        .font(.system(size: 13))
                        .foregroundColor(Theme.textSecondary)

                    Picker("", selection: $selectedDeviceID) {
                        ForEach(devices) { device in
                            Text(device.name)
                                .tag(device.uid)
                        }
                    }
                    .pickerStyle(.menu)
                    .onChange(of: selectedDeviceID) { _, newValue in
                        if let device = devices.first(where: { $0.uid == newValue }) {
                            config.audioDeviceIndex = device.index
                            config.audioDeviceName = device.name
                            config.save()
                            statusMessage = "Saved: \(device.name)"
                        }
                    }

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.system(size: 12))
                            .foregroundColor(Theme.green)
                    }
                }
                .padding(24)
                .background(Theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius))
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.cardRadius)
                        .stroke(Theme.border, lineWidth: 1)
                )
            }
            .padding(20)
        }
        .onAppear { loadDevices() }
    }

    private func loadDevices() {
        // Use AVCaptureDevice to enumerate audio inputs
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.microphone, .external],
            mediaType: .audio,
            position: .unspecified
        )

        devices = discoverySession.devices.enumerated().map { index, device in
            AudioDevice(
                uid: device.uniqueID,
                name: device.localizedName,
                index: index
            )
        }

        // Select current device
        if let savedName = config.audioDeviceName,
           let device = devices.first(where: { $0.name == savedName }) {
            selectedDeviceID = device.uid
        } else if let first = devices.first {
            selectedDeviceID = first.uid
        }
    }
}

struct AudioDevice: Identifiable {
    let uid: String
    let name: String
    let index: Int
    var id: String { uid }
}
