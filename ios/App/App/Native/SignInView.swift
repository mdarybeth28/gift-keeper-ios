import SwiftUI

/// The front door — the web app's auth screen in native dress:
/// Sign in / Create account tabs, the server's own error words in
/// the web's friendly translations, and a Forgot password door.
/// Sign-up mirrors the web's createPassword exactly: a full email,
/// at least 8 characters, typed twice and matching — and because
/// Gift's sign-ups confirm by email, a made account that has no
/// session yet lands on the web's own answer: "Your password is
/// set! … tap the link in it, then come back and Sign in."
struct SignInView: View {
    @EnvironmentObject private var session: SessionStore

    private enum Tab {
        case signIn, create
    }

    @State private var tab: Tab = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var newEmail = ""
    @State private var newPassword = ""
    @State private var newPassword2 = ""
    @State private var isWorking = false
    @State private var createError: String?
    @State private var notice: String?

    var body: some View {
        Form {
            Section {
                Picker("Sign in or create account", selection: $tab) {
                    Text("Sign in").tag(Tab.signIn)
                    Text("Create account").tag(Tab.create)
                }
                .pickerStyle(.segmented)
            }
            if let notice {
                Section {
                    Text(notice)
                        .foregroundStyle(Theme.brown)
                        .font(.subheadline)
                }
            }
            if tab == .signIn {
                signInSections
            } else {
                createSections
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.page)
    }

    // MARK: - Sign in

    @ViewBuilder
    private var signInSections: some View {
        Section {
            Text("Sign in with the same email and password you use on giftkeepersecret.com.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        Section(header: Text("Your account")) {
            TextField("Email", text: $email)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            SecureField("Password", text: $password)
                .textContentType(.password)
        }
        if let error = session.lastError {
            Section {
                Text(error)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
        }
        Section {
            Button {
                isWorking = true
                notice = nil
                let pw = password
                Task {
                    await session.signIn(email: email.trimmingCharacters(in: .whitespaces), password: pw)
                    isWorking = false
                }
            } label: {
                HStack {
                    Spacer()
                    if isWorking { ProgressView() }
                    Text("Sign in")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(isWorking || email.isEmpty || password.isEmpty)

            Button("Forgot password") {
                Task { await forgotPassword() }
            }
            .disabled(isWorking || email.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    private func forgotPassword() async {
        let address = email.trimmingCharacters(in: .whitespaces)
        guard Self.validEmail(address) else {
            notice = "Type your email first, then choose Forgot password."
            return
        }
        isWorking = true
        defer { isWorking = false }
        if await session.sendPasswordReset(email: address) {
            notice = "A sign-in link is on its way to \(address). Open it to set a new password."
        }
    }

    // MARK: - Create account

    @ViewBuilder
    private var createSections: some View {
        Section {
            Text("New to Gift Keeper? Make your account right here — one email, one password.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        Section(header: Text("Create your account")) {
            TextField("Email", text: $newEmail)
                .textContentType(.emailAddress)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)
                .autocorrectionDisabled()
            SecureField("Password (at least 8 characters)", text: $newPassword)
                .textContentType(.newPassword)
            SecureField("Type the password again", text: $newPassword2)
                .textContentType(.newPassword)
        }
        if let createError {
            Section {
                Text(createError)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }
        }
        Section {
            Button {
                Task { await createAccount() }
            } label: {
                HStack {
                    Spacer()
                    if isWorking { ProgressView() }
                    Text("Create my password")
                        .fontWeight(.semibold)
                    Spacer()
                }
            }
            .disabled(isWorking || newEmail.isEmpty || newPassword.isEmpty || newPassword2.isEmpty)
        }
        Section {
            Text("We email you a confirmation link when you create your account. If it isn't in your inbox in a minute or two, check your spam folder — then sign in here with the password you just made.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func createAccount() async {
        createError = nil
        notice = nil
        let address = newEmail.trimmingCharacters(in: .whitespaces)
        guard Self.validEmail(address) else {
            createError = "Type a full email address, like name@example.com."
            return
        }
        guard newPassword.count >= 8 else {
            createError = "Use at least 8 characters."
            return
        }
        guard newPassword == newPassword2 else {
            createError = "The two passwords don't match."
            return
        }
        isWorking = true
        defer { isWorking = false }
        let pw = newPassword
        let outcome = await session.signUp(email: address, thePassword: pw)
        switch outcome {
        case .signedIn:
            break // The approval gate takes it from here.
        case .needsEmailConfirmation:
            notice = "Your password is set! We just sent a confirmation email to \(address) — tap the link in it, then come back and Sign in with the password you just created."
            tab = .signIn
            email = address
        case .failed:
            createError = session.lastError
        }
    }

    /// The web's validEmail.
    static func validEmail(_ value: String) -> Bool {
        let pattern = #"^[^\s@]+@[^\s@]+\.[^\s@]+$"#
        return value.range(of: pattern, options: .regularExpression) != nil
    }
}
