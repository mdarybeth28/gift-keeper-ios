import SwiftUI

/// The More tab — the app's own settings and doors, natively:
/// - App lock (Face ID / passcode — the web's PIN promise in
///   native form).
/// - The list doors the web keeps one tap away: Upcoming,
///   Budget, Archived.
/// - Tell Mary (the feedback door, photo and all).
/// - Your account: the signed-in email, sign out, and Delete my
///   account (the web's deleteMyAccount: type your email to
///   confirm, the delete-account function does the rest).
///
/// The bundled placeholder web page that used to fill this tab's
/// lower half is retired: everything it promised (add/edit
/// forms, the wish list, the readers, help) is native now, so
/// there is nothing left for it to stand in for.
struct MoreView: View {
    @EnvironmentObject private var appLock: AppLockManager
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var giftStore: GiftListStore

    @State private var showFeedback = false
    @State private var showDeleteAccount = false

    var body: some View {
        NavigationStack {
            List {
                Section(header: Text("Your lists")) {
                    NavigationLink {
                        UpcomingView()
                    } label: {
                        Label("Upcoming occasions", systemImage: "calendar.badge.clock")
                    }
                    NavigationLink {
                        BudgetView()
                    } label: {
                        Label("Gift budget", systemImage: "chart.pie")
                    }
                    NavigationLink {
                        ArchivedView()
                    } label: {
                        Label("Archived", systemImage: "archivebox")
                    }
                    Button {
                        showFeedback = true
                    } label: {
                        Label("Tell Mary something", systemImage: "envelope")
                    }
                }

                Section(header: Text("App lock")) {
                    Toggle(isOn: Binding(
                        get: { appLock.isEnabled },
                        set: { appLock.setEnabled($0) }
                    )) {
                        Text("Lock with Face ID / passcode")
                            .font(.subheadline)
                    }
                    .disabled(!appLock.canUseDeviceAuth)
                    Text(appLock.canUseDeviceAuth
                         ? "When this is on, Gift Keeper asks for Face ID (or this phone's passcode) when you open it, and again if you've been away a few minutes — so nobody can peek at your gifts. It's off unless you turn it on."
                         : "This phone has no Face ID or passcode set up, so the app lock can't be turned on here.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if session.isSignedIn {
                    Section(header: Text("Your account")) {
                        LabeledContent("Signed in as", value: session.currentEmail ?? "")
                        Button("Sign out") {
                            Task { await session.signOut() }
                        }
                    }
                    Section {
                        Button("Delete my account", role: .destructive) {
                            showDeleteAccount = true
                        }
                        Text("Deletes your account and your gift list for good. This can't be undone.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let text = giftStore.saveStatusText {
                    Section {
                        Text(text)
                            .font(.caption)
                            .foregroundStyle(giftStore.saveState == .failed ? Theme.warn : Theme.muted)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page)
            .navigationTitle("More")
            .sheet(isPresented: $showFeedback) {
                FeedbackView()
            }
            .sheet(isPresented: $showDeleteAccount) {
                DeleteAccountView()
            }
        }
    }
}

/// Delete my account — the web's two-step door: the words first,
/// then type the email you're signed in with to prove it. Only
/// an exact match (case aside) arms the delete button, and a
/// mismatch deletes nothing. On success the delete-account
/// function has removed the account and the app signs out.
struct DeleteAccountView: View {
    @EnvironmentObject private var session: SessionStore
    @EnvironmentObject private var giftStore: GiftListStore
    @Environment(\.dismiss) private var dismiss

    @State private var typedEmail = ""
    @State private var error: String?
    @State private var isDeleting = false
    @State private var deleted = false

    var body: some View {
        NavigationStack {
            Form {
                if deleted {
                    Section {
                        Text("Your account and gift list are deleted. Thank you for keeping them with us 🎁")
                            .font(.subheadline)
                            .foregroundStyle(Theme.brown)
                    }
                } else {
                    Section {
                        Text("This deletes your Gift Keeper account and your whole gift list — every person, gift, photo and tracking number — for good. It can't be undone.")
                            .font(.subheadline)
                    }
                    Section(header: Text("Type your email to confirm")) {
                        TextField("Your email", text: $typedEmail)
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .autocapitalization(.none)
                            .autocorrectionDisabled()
                    }
                    if let error {
                        Section {
                            Text(error).foregroundStyle(.red).font(.subheadline)
                        }
                    }
                    Section {
                        Button(role: .destructive) {
                            Task { await deleteAccount() }
                        } label: {
                            HStack {
                                Spacer()
                                if isDeleting { ProgressView() }
                                Text("Yes, delete everything").fontWeight(.semibold)
                                Spacer()
                            }
                        }
                        .disabled(isDeleting)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page)
            .navigationTitle("Delete my account")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(deleted ? "Done" : "Keep my account") { dismiss() }
                }
            }
        }
    }

    private func deleteAccount() async {
        guard let email = session.currentEmail else { return }
        guard typedEmail.trimmingCharacters(in: .whitespaces).lowercased() == email.lowercased() else {
            error = "That email doesn't match the one you're signed in with, so nothing was deleted."
            return
        }
        guard let token = await session.validAccessToken() else {
            error = "Your sign-in expired. Please sign out and sign in again."
            return
        }
        isDeleting = true
        defer { isDeleting = false }
        do {
            let data = try await GiftWriteService.invoke(accessToken: token, function: "delete-account", body: [:])
            if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let inner = object["error"] as? String {
                throw NSError(domain: "GiftKeeperDelete", code: 0, userInfo: [NSLocalizedDescriptionKey: inner])
            }
            giftStore.clear()
            deleted = true
            await session.signOut()
        } catch {
            self.error = "Deleting didn't finish — your account is still here, nothing was removed. Try once more, or tap Tell Mary above and Marybeth will delete it for you. (\(SessionStore.friendlyMessage(error.localizedDescription)))"
        }
    }
}
