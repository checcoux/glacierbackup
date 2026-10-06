import Foundation

/// Dati prodotti dal modello CloudFormation (Support/cloudformation.yaml) nell'output
/// `AppConfiguration`, che l'utente incolla nella configurazione guidata.
struct SetupConfiguration: Equatable {
    var region: String
    var bucket: String
    var credentials: AWSCredentials

    /// Formato: `glacierbackup:regione:bucket:accessKeyID:secretAccessKey`
    init?(pasted: String) {
        let fields = pasted.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: ":", omittingEmptySubsequences: false)
            .map(String.init)
        guard fields.count == 5, fields[0] == "glacierbackup", !fields.contains("") else { return nil }
        region = fields[1]
        bucket = fields[2]
        credentials = AWSCredentials(accessKeyID: fields[3], secretAccessKey: fields[4])
        guard AppSettings(region: region, bucket: bucket).isValid else { return nil }
    }
}

enum SetupLink {
    /// URL S3 pubblico su cui è ospitato Support/cloudformation.yaml.
    /// CloudFormation accetta solo modelli ospitati su S3.
    static let templateURL: String? =
        "https://checcoux-prod-1.s3.eu-central-1.amazonaws.com/misc/cloudformation.yaml"

    static let signUp = URL(string: "https://portal.aws.amazon.com/billing/signup")!

    static let regions: [(id: String, name: String)] = [
        ("eu-west-1", "Europa (Irlanda)"),
        ("eu-central-1", "Europa (Francoforte)"),
        ("eu-south-1", "Europa (Milano)"),
        ("us-east-1", "Stati Uniti (Virginia)"),
        ("us-west-2", "Stati Uniti (Oregon)"),
    ]

    /// Pagina della console AWS che crea lo stack con il modello già selezionato.
    static func quickCreate(region: String, templateURL: String? = templateURL) -> URL? {
        guard let templateURL else { return nil }
        return URL(string: "https://\(region).console.aws.amazon.com/cloudformation/home?region=\(region)"
            + "#/stacks/quickcreate?stackName=GlacierBackup&templateURL=\(SigV4.awsEncode(templateURL))")
    }
}
