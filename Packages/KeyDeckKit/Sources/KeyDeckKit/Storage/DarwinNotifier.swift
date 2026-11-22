import Foundation

/// Cross-process notification bridge between KeyDeckApp and KeyDeckKeyboard via CFNotificationCenter.
public final class DarwinNotifier: @unchecked Sendable {
    public static func post(_ name: String) {
        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterPostNotification(
            center,
            CFNotificationName(name as CFString),
            nil,
            nil,
            true
        )
    }

    private final class ObserverBox {
        let handler: @Sendable () -> Void
        init(handler: @escaping @Sendable () -> Void) {
            self.handler = handler
        }
    }

    private var registrations: [(name: String, box: ObserverBox)] = []
    private let lock = NSLock()

    public init() {}

    deinit {
        removeAll()
    }

    public func observe(_ name: String, handler: @escaping @Sendable () -> Void) {
        let box = ObserverBox(handler: handler)
        let observerPointer = Unmanaged.passUnretained(box).toOpaque()

        lock.lock()
        registrations.append((name: name, box: box))
        lock.unlock()

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        CFNotificationCenterAddObserver(
            center,
            observerPointer,
            { _, observer, _, _, _ in
                guard let observer else { return }
                let box = Unmanaged<ObserverBox>.fromOpaque(observer).takeUnretainedValue()
                box.handler()
            },
            name as CFString,
            nil,
            .deliverImmediately
        )
    }

    public func removeAll() {
        lock.lock()
        let current = registrations
        registrations.removeAll()
        lock.unlock()

        let center = CFNotificationCenterGetDarwinNotifyCenter()
        for item in current {
            let observerPointer = Unmanaged.passUnretained(item.box).toOpaque()
            CFNotificationCenterRemoveObserver(
                center,
                observerPointer,
                CFNotificationName(item.name as CFString),
                nil
            )
        }
    }
}
