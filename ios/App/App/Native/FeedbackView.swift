import SwiftUI
import PhotosUI

/// The Tell Mary door — the web app's feedback view, and the
/// landing place for every "Send this photo to Mary" fallback
/// (the web's carry-to-feedback doors): the photo arrives already
/// attached, with a starter sentence waiting in an empty message
/// box; words somebody typed are never replaced.
///
/// Sending mirrors the web's sendFeedback step for step:
/// 1. The message lands in the `feedback` table first
///    (message, the optional typed sender email, the account's
///    email), then send-feedback emails it. If the email copy
///    fails, the message is still saved and the words say so.
/// 2. An attached photo rides along AFTER: the help-photos chain
///    (bucket upload under your own folder, a help_photos row,
///    send-help-photo). A photo that won't go up never takes the
///    message down with it.
struct FeedbackView: View {
    @EnvironmentObject private var session: SessionStore
    @Environment(\.dismiss) private var dismiss

    var initialMessage: String = ""
    var initialPhotoData: Data? = nil

    @State private var message = ""
    @State private var senderEmail = ""
    @State private var photoItem: PhotosPickerItem?
    @State private var photoData: Data?
    @State private var error: String?
    @State private var photoNote: String?
    @State private var isSending = false
    @State private var sent = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Questions, ideas, something not working — or a photo the reader couldn't read? Write it here; it goes straight to Mary.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Section {
                    TextField("Your message", text: $message, axis: .vertical)
                        .lineLimit(3...8)
                    TextField("Your email (optional)", text: $senderEmail)
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .autocapitalization(.none)
                        .autocorrectionDisabled()
                }
                Section(header: Text("Photo (optional)")) {
                    if let photoData, let image = UIImage(data: photoData) {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 180)
                        Button("Take the photo off", role: .destructive) {
                            self.photoData = nil
                            photoItem = nil
                        }
                    } else {
                        PhotosPicker(selection: $photoItem, matching: .images, photoLibrary: .shared()) {
                            Label("Attach a photo", systemImage: "photo.on.rectangle.angled")
                        }
                    }
                    if let photoNote {
                        Text(photoNote).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let error {
                    Section {
                        Text(error).foregroundStyle(.red).font(.subheadline)
                    }
                }
                if sent {
                    Section {
                        Text("Sent ✓ Thank you — Mary has your message.")
                            .foregroundStyle(Theme.brown)
                            .font(.subheadline)
                    }
                }
                Section {
                    Button {
                        Task { await send() }
                    } label: {
                        HStack {
                            Spacer()
                            if isSending { ProgressView() }
                            Text("Send feedback").fontWeight(.semibold)
                            Spacer()
                        }
                    }
                    .disabled(isSending || message.trimmingCharacters(in: .whitespacesAndNewlines).count < 3)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.page)
            .navigationTitle("Tell Mary")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(sent ? "Done" : "Cancel") { dismiss() }
                }
            }
            .onAppear {
                if message.isEmpty { message = initialMessage }
                if photoData == nil { photoData = initialPhotoData }
            }
            .onChange(of: photoItem) { newItem in
                guard let newItem else { return }
                Task {
                    if let raw = try? await newItem.loadTransferable(type: Data.self) {
                        photoData = GiftPhoto.preparedJPEG(from: raw)
                    }
                }
            }
        }
    }

    private func send() async {
        let text = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= 3 else {
            error = "Type a sentence or two about what you'd like to say."
            return
        }
        let sender = senderEmail.trimmingCharacters(in: .whitespaces)
        if !sender.isEmpty && !SignInView.validEmail(sender) {
            error = "That email doesn't look right. Leave it blank if you'd rather not give one."
            return
        }
        guard let token = await session.validAccessToken() else {
            error = "Your sign-in expired. Please sign out and sign in again."
            return
        }
        isSending = true
        defer { isSending = false }
        do {
            let emailSent = try await GiftWriteService.sendFeedback(
                accessToken: token, message: text, senderEmail: sender,
                userEmail: session.currentEmail)
            if let photoData, let userID = session.currentUserID {
                do {
                    try await GiftWriteService.sendPhotoToMary(
                        accessToken: token, userID: userID, userEmail: session.currentEmail,
                        note: text, imageData: photoData)
                    self.photoData = nil
                } catch {
                    // The message went through; the photo didn't.
                    photoNote = "Your message went through — the photo didn't. You can try the photo again."
                    sent = true
                    if !emailSent {
                        photoNote = "Your message is saved and Mary will see it in Gift Keeper (the email copy didn't go out) — but the photo didn't send. You can try the photo again."
                    }
                    return
                }
            }
            sent = true
            message = ""
            if !emailSent {
                photoNote = "Your message is saved. Mary will see it in Gift Keeper. (The email copy didn't go out.)"
            }
        } catch {
            self.error = "Your message didn't save. Try again in a moment."
        }
    }
}
