//
//  BroadcastPickerView.swift
//  Huiyijilu
//
//  Wraps RPSystemBroadcastPickerView for use in SwiftUI.
//  Shows the system "开始直播 / 结束直播" dialog for system-wide recording.
//

import SwiftUI
import ReplayKit

/// SwiftUI wrapper for `RPSystemBroadcastPickerView`.
/// When tapped, the system presents the broadcast start/stop sheet.
struct BroadcastPickerView: UIViewRepresentable {

    /// The preferred broadcast extension bundle identifier.
    var preferredExtension: String = SystemAudioRecorderService.broadcastExtensionBundleID

    /// Whether to show the microphone toggle in the picker.
    var showsMicrophoneButton: Bool = true

    func makeUIView(context: Context) -> RPSystemBroadcastPickerView {
        let picker = RPSystemBroadcastPickerView(frame: CGRect(x: 0, y: 0, width: 60, height: 60))
        picker.preferredExtension = preferredExtension
        picker.showsMicrophoneButton = showsMicrophoneButton
        // Make the built-in button invisible — we overlay our own styled button
        for subview in picker.subviews {
            if let button = subview as? UIButton {
                button.imageView?.tintColor = .clear
                button.setImage(nil, for: .normal)
                button.setTitle(nil, for: .normal)
            }
        }
        return picker
    }

    func updateUIView(_ uiView: RPSystemBroadcastPickerView, context: Context) {}
}

/// A styled broadcast control button.
/// Overlays a visible SwiftUI button on top of the invisible RPSystemBroadcastPickerView.
struct BroadcastButton: View {
    var isRecording: Bool

    var body: some View {
        ZStack {
            // The invisible system picker (handles the actual broadcast start/stop)
            BroadcastPickerView()
                .frame(width: 80, height: 80)

            // Our visible styled button on top
            Image(systemName: isRecording ? "stop.circle.fill" : "record.circle")
                .font(.system(size: 64))
                .foregroundStyle(isRecording ? .red : .purple)
                .allowsHitTesting(false) // Let taps pass through to the picker
        }
        .frame(width: 80, height: 80)
    }
}
