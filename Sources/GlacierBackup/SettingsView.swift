import SwiftUI

struct SettingsView: View {
    private enum TestResult {
        case running
        case success
        case failure(String)
    }

    @EnvironmentObject private var state: AppState
    @State private var accessKeyID = ""
    @State private var secretAccessKey = ""
    @State private var draft = AppSettings()
    @State private var testResult: TestResult?
    @State private var saveError: String?

    var body: some View {
        Form {
            Section("Credenziali AWS") {
                TextField("Access Key ID", text: $accessKeyID)
                    .autocorrectionDisabled()
                SecureField("Secret Access Key", text: $secretAccessKey)
            }
            Section("Destinazione") {
                TextField("Regione", text: $draft.region, prompt: Text("eu-west-1"))
                    .autocorrectionDisabled()
                TextField("Bucket", text: $draft.bucket, prompt: Text("nome-del-bucket"))
                    .autocorrectionDisabled()
                TextField("Prefisso", text: $draft.prefix, prompt: Text("backup"))
                    .autocorrectionDisabled()
                Picker("Classe di archiviazione", selection: $draft.storageClass) {
                    ForEach(StorageClass.allCases) { storageClass in
                        Text(storageClass.label).tag(storageClass)
                    }
                }
            }
            Section {
                Toggle("Comprimi gli archivi (gzip)", isOn: $draft.compress)
            } footer: {
                Text("Utile per documenti e codice; inutile e più lento per foto, video e file già compressi.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Verifica connessione", action: testConnection)
                        .disabled(!isComplete)
                    testResultView
                    Spacer()
                    Button("Salva", action: save)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!isComplete || state.isRunning)
                }
                if let saveError {
                    Text(saveError)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 500)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            draft = state.settings
            accessKeyID = state.credentials?.accessKeyID ?? ""
            secretAccessKey = state.credentials?.secretAccessKey ?? ""
        }
    }

    @ViewBuilder
    private var testResultView: some View {
        switch testResult {
        case .running:
            ProgressView()
                .controlSize(.small)
        case .success:
            Label("Connessione riuscita", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case let .failure(message):
            Label(message, systemImage: "xmark.circle.fill")
                .foregroundStyle(.red)
                .font(.caption)
        case nil:
            EmptyView()
        }
    }

    private var draftCredentials: AWSCredentials {
        AWSCredentials(
            accessKeyID: accessKeyID.trimmingCharacters(in: .whitespacesAndNewlines),
            secretAccessKey: secretAccessKey.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    private var isComplete: Bool {
        draft.isValid && !draftCredentials.accessKeyID.isEmpty && !draftCredentials.secretAccessKey.isEmpty
    }

    private func testConnection() {
        let client = S3Client(credentials: draftCredentials, region: draft.region, bucket: draft.bucket)
        testResult = .running
        Task {
            do {
                try await client.headBucket()
                testResult = .success
            } catch {
                testResult = .failure(error.localizedDescription)
            }
        }
    }

    private func save() {
        do {
            if draftCredentials != state.credentials {
                try state.saveCredentials(draftCredentials)
            }
            state.settings = draft
            saveError = nil
            NSApp.keyWindow?.close()
        } catch {
            saveError = error.localizedDescription
        }
    }
}
