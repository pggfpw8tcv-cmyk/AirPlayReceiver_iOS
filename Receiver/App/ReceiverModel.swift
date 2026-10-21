import AVFoundation
import SwiftUI

// Engine delegate events are delivered on the main queue.
final class ReceiverModel: NSObject, ObservableObject, ReceiverEngineDelegate {
    @Published var name: String = UserDefaults.standard.string(forKey: "receiverName") ?? "iOS Receiver"
    @Published var requirePIN = true
    @Published private(set) var status = "Gestoppt"
    @Published private(set) var active = false
    @Published private(set) var pin = ""
    @Published private(set) var diagnostics = [String]()
    let engine = ReceiverEngine()
    private var observers = [NSObjectProtocol]()

    override init() {
        super.init()
        engine.delegate = self
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            guard let kind = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  kind == AVAudioSession.InterruptionType.began.rawValue else { return }
            self?.engine.stop()
            self?.receiverDiagnostic("Gestoppt, weil der Ton unterbrochen wurde. Mit „Empfang starten“ erneut verbinden.")
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            guard let reason = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
                  reason == AVAudioSession.RouteChangeReason.oldDeviceUnavailable.rawValue else { return }
            self?.engine.stop()
            self?.receiverDiagnostic("Audioausgabe getrennt. Bitte mit „Empfang starten“ erneut verbinden.")
        })
        observers.append(center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: nil, queue: .main) { [weak self] _ in
            self?.engine.stop()
            self?.receiverDiagnostic("Der Audiodienst wurde neu gestartet. Bitte mit „Empfang starten“ erneut verbinden.")
        })
    }

    deinit { for observer in observers { NotificationCenter.default.removeObserver(observer) } }

    func start() {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        UserDefaults.standard.set(trimmed, forKey: "receiverName")
        let identity: Data
        if let saved = UserDefaults.standard.data(forKey: "receiverIdentity"), saved.count == 6 {
            identity = saved
        } else {
            var bytes = (0..<6).map { _ in UInt8.random(in: .min ... .max) }
            bytes[0] = (bytes[0] | 2) & 0xfe // Locally administered, unicast identity; not the device MAC.
            identity = Data(bytes)
            UserDefaults.standard.set(identity, forKey: "receiverIdentity")
        }
        do {
            var storage = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                      appropriateFor: nil, create: true)
                .appendingPathComponent("Receiver", isDirectory: true)
            try FileManager.default.createDirectory(at: storage, withIntermediateDirectories: true)
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try storage.setResourceValues(values)
            engine.start(withName: trimmed, identity: identity, storageURL: storage, requirePIN: requirePIN)
        } catch {
            receiverStatus(error.localizedDescription, active: false)
        }
    }

    func receiverStatus(_ status: String, active: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        self.status = status
        self.active = active
        UIApplication.shared.isIdleTimerDisabled = active
    }
    func receiverPIN(_ pin: String) { self.pin = pin }
    func receiverDiagnostic(_ message: String) {
        diagnostics.append("\(Date().formatted(date: .omitted, time: .standard)) \(message)")
        if diagnostics.count > 100 { diagnostics.removeFirst(diagnostics.count - 100) }
    }
}
