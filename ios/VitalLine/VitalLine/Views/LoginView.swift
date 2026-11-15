import SwiftUI

// First screen on a fresh start: sign in, or create an account with the team code.
// Accounts are checked by the backend (Supabase Auth behind it); the app holds no keys.
// If the backend has sign-in turned off (no Supabase keys), the app skips this screen.
struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @AppStorage("backendURL") private var backendURL = ""

    @State private var creating = false
    @State private var email = ""
    @State private var password = ""
    @State private var teamCode = ""
    @State private var message: String?
    @State private var working = false
    @State private var showServer = API.defaultBaseURL.isEmpty   // phones need the address first

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                Image("VitalLineLogo")
                    .resizable().scaledToFit()
                    .frame(height: 64)
                    .padding(.top, 48)
                Text("Decision aid for EMS crews. Prototype, not a medical device.")
                    .font(.footnote).foregroundStyle(.textSecondary)
                    .multilineTextAlignment(.center)

                Picker("Mode", selection: $creating) {
                    Text("Sign In").tag(false)
                    Text("Create Account").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.top, 8)

                VStack(spacing: 12) {
                    field("Email", text: $email, keyboard: .emailAddress, content: .username)
                    SecureField("Password", text: $password)
                        .textContentType(creating ? .newPassword : .password)
                        .padding().background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
                    if creating {
                        field("Team code", text: $teamCode, keyboard: .asciiCapable, content: .oneTimeCode)
                        Text("The team code is the demo token from the backend. Password: 8 characters or more.")
                            .font(.caption).foregroundStyle(.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if let message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(.caution)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button(working ? "Please wait…" : (creating ? "Create Account" : "Sign In")) { submit() }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(working || email.isEmpty || password.isEmpty)

                DisclosureGroup("Backend address", isExpanded: $showServer) {
                    field(API.defaultBaseURL.isEmpty ? "Tunnel address (https://...)" : API.defaultBaseURL,
                          text: $backendURL, keyboard: .URL, content: .URL)
                        .padding(.top, 8)
                    Text("On a phone, paste the address that scripts/run_tunnel.sh prints on the Mac.")
                        .font(.caption).foregroundStyle(.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .foregroundStyle(.textSecondary)
                .tint(.brandPrimary)
            }
            .padding()
        }
        .vitalScreen()
        .task { await auth.checkBackend() }
    }

    private func field(_ title: String, text: Binding<String>, keyboard: UIKeyboardType,
                       content: UITextContentType) -> some View {
        TextField(title, text: text)
            .keyboardType(keyboard)
            .textContentType(content)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .foregroundStyle(.textPrimary)
            .padding().background(Color.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func submit() {
        working = true
        message = nil
        Task {
            let result = await API.signIn(email: email, password: password,
                                          teamCode: creating ? teamCode : nil, create: creating)
            working = false
            switch result {
            case .success(let session): auth.signedIn(session)
            case .failure(let failure): message = failure.message
            }
        }
    }
}
