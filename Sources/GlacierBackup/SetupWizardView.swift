import AppKit
import SwiftUI

struct SetupWizardView: View {
    private enum Step: Int {
        case account, create, paste, done
    }

    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var step = Step.account
    @State private var region = SetupLink.regions[0].id
    @State private var pasted = ""
    @State private var isChecking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 14) {
                if step != .done {
                    Text("Passo \(step.rawValue + 1) di 3")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, minHeight: 300, alignment: .topLeading)
            Divider()
            buttons
                .padding(16)
        }
        .frame(width: 540)
    }

    @ViewBuilder
    private var content: some View {
        switch step {
        case .account:
            title("Ti serve un account AWS")
            Text("I backup vengono conservati sul tuo account Amazon Web Services, in Glacier Deep Archive: "
                + "circa 1 $ al mese per ogni terabyte.")
            Text("Se non hai ancora un account, crealo ora: servono un'email e una carta di credito. "
                + "Poi torna qui e prosegui.")
            Button("Crea un account AWS") { openURL(SetupLink.signUp) }
        case .create:
            title("Crea lo spazio per i backup")
            Picker("Dove conservare i backup", selection: $region) {
                ForEach(SetupLink.regions, id: \.id) { region in
                    Text(region.name).tag(region.id)
                }
            }
            .fixedSize()
            instructions([
                "Premi il pulsante qui sotto: si apre la console AWS. Accedi, se richiesto.",
                "In fondo alla pagina spunta la casella che autorizza la creazione di risorse IAM.",
                "Premi “Crea stack” (Create stack) e attendi circa un minuto, finché lo stato diventa "
                    + "CREATE_COMPLETE.",
            ])
            Button("Apri la console AWS") {
                if let url = SetupLink.quickCreate(region: region) { openURL(url) }
            }
            .disabled(SetupLink.quickCreate(region: region) == nil)
            Text("Vengono creati un bucket S3 privato e una chiave di accesso che può solo caricare file "
                + "in quel bucket.")
                .font(.caption)
                .foregroundStyle(.secondary)
        case .paste:
            title("Collega l'app")
            instructions([
                "Nella pagina dello stack apri la scheda “Output” (Outputs).",
                "Copia per intero il valore di AppConfiguration.",
                "Incollalo qui sotto.",
            ])
            HStack {
                SecureField("glacierbackup:…", text: $pasted)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(connect)
                Button("Incolla") {
                    pasted = NSPasteboard.general.string(forType: .string) ?? ""
                }
            }
            if let error {
                Text(error)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .done:
            Label("Tutto pronto", systemImage: "checkmark.circle.fill")
                .font(.title2.bold())
                .foregroundStyle(.green)
            Text("L'app è collegata al bucket \(state.settings.bucket).")
            Text("Aggiungi le cartelle da salvare con il pulsante + e premi “Esegui backup”.")
        }
    }

    private var buttons: some View {
        HStack {
            if step != .done {
                Button("Annulla", role: .cancel) { dismiss() }
            }
            Spacer()
            if isChecking {
                ProgressView()
                    .controlSize(.small)
            }
            switch step {
            case .account:
                Button("Ho un account, continua") { step = .create }
                    .keyboardShortcut(.defaultAction)
            case .create:
                Button("Indietro") { step = .account }
                Button("Stack creato, continua") { step = .paste }
                    .keyboardShortcut(.defaultAction)
            case .paste:
                Button("Indietro") { step = .create }
                    .disabled(isChecking)
                Button("Collega", action: connect)
                    .keyboardShortcut(.defaultAction)
                    .disabled(pasted.isEmpty || isChecking)
            case .done:
                Button("Fine") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func title(_ text: String) -> some View {
        Text(text)
            .font(.title2.bold())
    }

    private func instructions(_ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(lines.enumerated()), id: \.offset) { index, line in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(index + 1).")
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                    Text(line)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func connect() {
        guard let configuration = SetupConfiguration(pasted: pasted) else {
            error = "Il valore incollato non è valido: copia per intero l'output AppConfiguration."
            return
        }
        error = nil
        isChecking = true
        Task {
            do {
                try await state.applySetup(configuration)
                pasted = ""
                step = .done
            } catch {
                self.error = error.localizedDescription
            }
            isChecking = false
        }
    }
}
