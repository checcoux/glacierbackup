import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            if state.folders.isEmpty {
                ContentUnavailableView(
                    "Nessuna cartella",
                    systemImage: "folder.badge.plus",
                    description: Text("Aggiungi le cartelle di cui vuoi fare il backup.")
                )
            } else {
                List {
                    ForEach($state.folders) { $folder in
                        FolderRow(folder: $folder)
                    }
                }
            }
            Divider()
            footer
        }
        .sheet(isPresented: $state.isShowingSetup) {
            SetupWizardView()
                .environmentObject(state)
        }
        .onAppear {
            if !state.isConfigured { state.isShowingSetup = true }
        }
        .toolbar {
            ToolbarItemGroup {
                Button("Aggiungi cartella", systemImage: "plus", action: chooseFolders)
                    .disabled(state.isRunning)
                SettingsLink {
                    Label("Impostazioni", systemImage: "gearshape")
                }
                if state.isRunning {
                    Button("Interrompi", systemImage: "stop.fill", action: state.cancelBackup)
                } else {
                    Button("Esegui backup", systemImage: "icloud.and.arrow.up", action: state.startBackup)
                        .disabled(!state.canStart)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            if state.isConfigured {
                Label(destination, systemImage: "externaldrive.badge.icloud")
                    .foregroundStyle(.secondary)
            } else {
                Label("App non ancora collegata ad AWS.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            }
            Spacer()
            if !state.isConfigured {
                Button("Configurazione guidata…") { state.isShowingSetup = true }
            }
        }
        .font(.callout)
        .lineLimit(1)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var destination: String {
        let prefix = state.settings.prefix.split(separator: "/").joined(separator: "/")
        return "s3://\(state.settings.bucket)/\(prefix) · \(state.settings.storageClass.rawValue)"
    }

    private func chooseFolders() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Aggiungi"
        if panel.runModal() == .OK {
            state.addFolders(panel.urls)
        }
    }
}

private struct FolderRow: View {
    @EnvironmentObject private var state: AppState
    @Binding var folder: BackupFolder

    var body: some View {
        HStack(spacing: 10) {
            Toggle("Includi nel backup", isOn: $folder.isSelected)
                .labelsHidden()
                .disabled(state.isRunning)
            Image(systemName: "folder.fill")
                .foregroundStyle(.tint)
                .font(.title2)
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name)
                    .font(.headline)
                Text(folder.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                statusView
            }
            Spacer()
            Button("Rimuovi", systemImage: "minus.circle") {
                state.removeFolder(folder.id)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .disabled(state.isRunning)
            .help("Rimuovi dall'elenco (non cancella nulla da S3)")
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var statusView: some View {
        switch state.statuses[folder.id] {
        case .queued:
            caption("In attesa…")
        case .measuring:
            caption("Calcolo dimensione…")
        case let .uploading(sent, estimated):
            ProgressView(value: min(Double(sent), Double(estimated)), total: Double(max(estimated, 1)))
            caption("Caricati \(bytes(sent)) di circa \(bytes(estimated))"
                + (state.settings.compress ? " (prima della compressione)" : ""))
        case .done:
            caption("Backup completato · \(lastBackup)", color: .green)
        case .cancelled:
            caption("Interrotto", color: .orange)
        case let .failed(message):
            caption(message, color: .red)
                .lineLimit(3)
                .textSelection(.enabled)
        case nil:
            caption(folder.lastBackupDate == nil ? "Mai eseguito" : "Ultimo backup: \(lastBackup)")
        }
    }

    private var lastBackup: String {
        guard let date = folder.lastBackupDate else { return "" }
        let size = folder.lastBackupSize.map { " · \(bytes($0))" } ?? ""
        return date.formatted(date: .abbreviated, time: .shortened) + size
    }

    private func caption(_ text: String, color: Color = .secondary) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(color)
    }

    private func bytes(_ count: Int64) -> String {
        count.formatted(.byteCount(style: .file))
    }
}
