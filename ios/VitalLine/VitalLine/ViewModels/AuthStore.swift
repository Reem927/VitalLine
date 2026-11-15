import Foundation
import Observation

// Who is signed in. The session token comes from the backend (POST /auth/login) and is sent
// with every request. Kept in UserDefaults so the crew stays signed in between launches.
// Read it with: @Environment(AuthStore.self) private var auth
@MainActor
@Observable
final class AuthStore {
    static let tokenKey = "sessionToken"
    static let emailKey = "sessionEmail"

    var email: String? = UserDefaults.standard.string(forKey: AuthStore.emailKey)
    var token: String? = UserDefaults.standard.string(forKey: AuthStore.tokenKey)
    var guest = false          // backend has sign-in turned off (no Supabase keys)

    var isSignedIn: Bool { token != nil || guest }

    func signedIn(_ session: API.AuthSession) {
        email = session.email
        token = session.token
        UserDefaults.standard.set(session.email, forKey: AuthStore.emailKey)
        UserDefaults.standard.set(session.token, forKey: AuthStore.tokenKey)
    }

    func signOut() {
        email = nil
        token = nil
        guest = false
        UserDefaults.standard.removeObject(forKey: AuthStore.emailKey)
        UserDefaults.standard.removeObject(forKey: AuthStore.tokenKey)
    }

    // On launch and on the sign-in screen: skip sign-in when the backend has it off, and
    // drop a saved session the backend no longer knows.
    func checkBackend() async {
        if API.useMock { guest = true; return }
        guard let health = await API.health() else { return }    // unreachable: stay as we are
        if health.auth == false {
            guest = true
        } else if token != nil, await API.sessionIsValid() == false {
            signOut()
        }
    }
}
