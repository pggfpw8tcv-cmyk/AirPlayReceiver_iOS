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
                    Button { fullscreen.toggle() } label: {
                        Image(systemName: fullscreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                            .padding(14).background(.ultraThinMaterial, in: Circle()).padding()
                    }
                    .accessibilityLabel(fullscreen ? "全画面を終了" : "全画面表示")
                }
                .frame(height: fullscreen ? geometry.size.height : geometry.size.height * 0.45)
                if !fullscreen {
                    Form {
                        Section("AirPlay Receiver") {
                            Label(receiver.status, systemImage: receiver.active ? "airplayvideo" : "power")
                            TextField("受信名", text: $receiver.name).disabled(receiver.active)
                            Toggle("接続時にPINを要求", isOn: $receiver.requirePIN).disabled(receiver.active)
                            if !receiver.pin.isEmpty {
                                Text(receiver.pin).font(.largeTitle.monospacedDigit()).textSelection(.enabled)
                            }
                            Button(receiver.active ? "受信停止" : "受信開始") {
                                if receiver.active { receiver.engine.stop() } else { receiver.start() }
                            }
                            .disabled(receiver.status == "停止処理中…")
                            Text("同じWi-Fiの送信端末で「画面ミラーリング」から受信名を選択してください。")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                        Section("開発状況と診断") {
                            Text("ミラーリング受信: 実機検証待ち\nAirPlay 2マルチルーム: 未実装")
                                .font(.footnote)
                            Button("AirPlay 2同期ポートを診断") { receiver.engine.probeAirPlay2Ports() }
                            if !receiver.diagnostics.isEmpty {
                                ShareLink("診断ログを共有", item: receiver.diagnostics.joined(separator: "\n"))
                                Text(receiver.diagnostics.suffix(8).joined(separator: "\n"))
                                    .font(.caption.monospaced()).textSelection(.enabled)
                            }
                        }
                    }
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}
