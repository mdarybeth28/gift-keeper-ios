import SwiftUI

/// The email + password sign-in form — the same sign-in the web app
/// uses, in native dress. Shows the server's own error words when a
/// sign-in fails; never invents a reason. (Gift Keeper signups are
/// created on the web; this form is sign-in only, same scope as the
/// Pet Keeper native build.)
struct SignInView: View {
    @EnvironmentObject private var session: SessionStore
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false

    var body: some View {
        Form {
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
                    Task {
                        await session.signIn(email: email.trimmingCharacters(in: .whitespaces),
                                             password: <redacted>
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
            }
        }
    }
}
