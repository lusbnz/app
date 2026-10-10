import LocalAuthentication
import Observation
import SwiftUI

/// Xác thực bằng Face ID, Touch ID hoặc mật mã máy. Tách ra để test không cần màn hình khóa thật.
protocol Authenticating: Sendable {
    /// Máy có mật mã hoặc sinh trắc học để khóa không.
    func isAvailable() -> Bool
    func authenticate(reason: String) async -> Bool
    var method: AuthMethod { get }
}

enum AuthMethod: Sendable {
    case faceID, touchID, passcode

    var title: String {
        switch self {
        case .faceID: "Face ID"
        case .touchID: "Touch ID"
        case .passcode: String(localized: "mật mã")
        }
    }
}

struct DeviceAuthenticator: Authenticating {
    func isAvailable() -> Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    /// Dùng `.deviceOwnerAuthentication` nên không có Face ID hay Face ID lỗi thì nhập mật mã được, không bị khóa mất dữ liệu.
    func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    var method: AuthMethod {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return .faceID
        case .touchID: return .touchID
        default: return .passcode
        }
    }
}

/// Khóa app: bật thì app khóa lúc mở và mỗi khi ra nền, phải xác thực để vào lại.
/// Intent ghi nhanh không mở giao diện nên vẫn ghi được khi app khóa, nhưng không đọc được gì ra.
@MainActor @Observable
final class AppLock {
    private(set) var isEnabled: Bool
    private(set) var isLocked: Bool
    private(set) var isAuthenticating = false
    /// App đang ở phía trước. Ra ngoài (đa nhiệm, trung tâm điều khiển) thì che màn hình để không lộ số liệu.
    private(set) var isActive = true

    @ObservationIgnored private var promptsOnActive = true
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let authenticator: any Authenticating

    init(defaults: UserDefaults = AppGroup.defaults, authenticator: any Authenticating = DeviceAuthenticator()) {
        self.defaults = defaults
        self.authenticator = authenticator
        let enabled = defaults.bool(forKey: SettingsKey.lockEnabled)
        isEnabled = enabled
        isLocked = enabled
    }

    /// Cần che toàn bộ màn hình: đang khóa, hoặc đã bật khóa mà app không ở phía trước.
    var shouldCover: Bool { isEnabled && (isLocked || !isActive) }
    var showsUnlockButton: Bool { isLocked && isActive }

    var method: AuthMethod { authenticator.method }
    var canEnable: Bool { authenticator.isAvailable() }

    /// Mở khóa bằng Face ID hoặc mật mã. Trả về true khi đã mở.
    @discardableResult
    func unlock() async -> Bool {
        guard isLocked else { return true }
        guard !isAuthenticating else { return false }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let ok = await authenticator.authenticate(reason: String(localized: "Mở khóa để xem chi tiêu của bạn."))
        if ok { isLocked = false }
        return ok
    }

    /// Bật hoặc tắt khóa; phải xác thực thành công mới đổi, nên người cầm máy không tắt được khóa.
    /// Trả về true khi đổi được.
    func setEnabled(_ enabled: Bool) async -> Bool {
        guard enabled != isEnabled else { return true }
        if enabled, !authenticator.isAvailable() { return false }
        let reason = enabled
            ? String(localized: "Xác nhận để bật khóa app.")
            : String(localized: "Xác nhận để tắt khóa app.")
        guard await authenticator.authenticate(reason: reason) else { return false }
        isEnabled = enabled
        isLocked = false
        defaults.set(enabled, forKey: SettingsKey.lockEnabled)
        return true
    }

    func scenePhaseChanged(_ phase: ScenePhase) {
        isActive = phase == .active
        if phase == .background {
            // Ra nền thì khóa lại, và lần vào app sau sẽ tự hiện hộp xác thực.
            if isEnabled { isLocked = true }
            promptsOnActive = true
        }
        // Hộp Face ID tự nó làm app qua trạng thái inactive rồi active; chỉ hỏi lại khi vừa từ nền trở về,
        // không thì bấm Hủy là hộp hiện lại mãi.
        if phase == .active, isLocked, promptsOnActive {
            promptsOnActive = false
            Task { await unlock() }
        }
    }
}

/// Màn che toàn bộ khi app khóa, và cả khi app ra ngoài (màn hình đa nhiệm) để không lộ số liệu.
struct LockView: View {
    @Environment(AppLock.self) private var lock

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "lock.fill")
                .font(.system(size: 44))
                .foregroundStyle(Color.xuTextSecondary)
                .accessibilityHidden(true)
            Text("Xu đang khóa")
                .font(.title2.weight(.semibold))
            if lock.showsUnlockButton {
                Button("Mở khóa bằng \(lock.method.title)") {
                    Task { await lock.unlock() }
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.horizontal, 48)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(Color.xuTextPrimary)
        .background(Color.xuBackground.ignoresSafeArea())
        .fontDesign(.rounded)
        .tint(Color.xuToggle)
    }
}

/// Đặt màn khóa trong một cửa sổ riêng nằm trên cùng, để che được cả các sheet đang mở.
@MainActor
final class LockWindowPresenter {
    static let shared = LockWindowPresenter()
    private var window: UIWindow?

    func update(covering: Bool, lock: AppLock, appearance: AppAppearance) {
        guard covering else {
            window?.isHidden = true
            window = nil
            return
        }
        if window == nil,
           let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
            let window = UIWindow(windowScene: scene)
            window.windowLevel = .alert + 1
            window.rootViewController = UIHostingController(rootView: LockView().environment(lock))
            self.window = window
        }
        window?.overrideUserInterfaceStyle = switch appearance {
        case .system: .unspecified
        case .light: .light
        case .dark: .dark
        }
        window?.isHidden = false
    }
}
