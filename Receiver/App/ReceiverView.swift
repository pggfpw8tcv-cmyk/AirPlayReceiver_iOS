import AVFoundation
import SwiftUI

private final class DisplayView: UIView {
    var display: AVSampleBufferDisplayLayer?
    override func layoutSubviews() {
        super.layoutSubviews()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        display?.frame = bounds
        CATransaction.commit()
    }
}

private struct VideoSurface: UIViewRepresentable {
    let display: AVSampleBufferDisplayLayer
    func makeUIView(context: Context) -> UIView {
        let view = DisplayView()
        view.backgroundColor = .black
        view.display = display
        view.layer.addSublayer(display)
        return view
    }
    func updateUIView(_ uiView: UIView, context: Context) { uiView.setNeedsLayout() }
}

struct ReceiverView: View {
    @EnvironmentObject private var receiver: ReceiverModel
    @State private var fullscreen = false

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                ZStack(alignment: .topTrailing) {
                    VideoSurface(display: receiver.engine.displayLayer)
                        .contentShape(Rectangle())
                        .onTapGesture { fullscreen.toggle() }
                    Button { fullscreen.toggle() } label: {
                        Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .padding(14).background(.ultraThinMaterial, in: Circle()).padding()
                    }
                    .accessibilityLabel(fullscreen ? "Vollbild beenden" : "Vollbild")
                }
                .frame(height: fullscreen ? geometry.size.height : geometry.size.height * 0.45)
                if !fullscreen {
                    Form {
                        Section("AirPlay Receiver") {
                            Label(receiver.status, systemImage: receiver.active ? "airplayvideo" : "power")
                            TextField("Empfängername", text: $receiver.name).disabled(receiver.active)
                            Toggle("PIN bei Verbindung verlangen", isOn: $receiver.requirePIN).disabled(receiver.active)
                            if !receiver.pin.isEmpty {
                                Text(receiver.pin).font(.largeTitle.monospacedDigit()).textSelection(.enabled)
                            }
                            Button(receiver.active ? "Empfang stoppen" : "Empfang starten") {
                                if receiver.active { receiver.engine.stop() } else { receiver.start() }
                            }
                            .disabled(receiver.status == "Wird beendet…")
                            Text("Wähle auf dem Sendegerät im selben WLAN unter „Bildschirmspiegelung“ den Empfängernamen aus.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Section("Entwicklungsstand und Diagnose") {
                            Text("Spiegelungsempfang: Test auf echtem Gerät steht aus\nAirPlay-2-Multiroom: nicht implementiert")
                                .font(.footnote)
                            Button("AirPlay-2-Synchronisierungsports prüfen") { receiver.engine.probeAirPlay2Ports() }
                            if !receiver.diagnostics.isEmpty {
                                ShareLink("Diagnoseprotokoll teilen", item: receiver.diagnostics.joined(separator: "\n"))
                                Text(receiver.diagnostics.suffix(8).joined(separator: "\n"))
                                    .font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden(fullscreen)
    }
}
