# Glacier Backup

App macOS (SwiftUI, nessuna dipendenza esterna) che archivia cartelle con `tar` e le carica su
Amazon S3 nella classe **Glacier Deep Archive**.

- Ogni backup crea un archivio completo: `prefisso/Cartella/Cartella_AAAA-MM-GG_HHMMSS.tar[.gz]`
- L'archivio viene inviato in streaming con upload multipart: non serve spazio libero su disco
- Le credenziali (Access Key ID + Secret) sono salvate nel Portachiavi

## Compilare

```bash
./build.sh                       # crea build/Glacier Backup.app
open "build/Glacier Backup.app"
swift test                       # test
```

Richiede macOS 14+ e Xcode. Il progetto si apre anche in Xcode da `Package.swift`.

## Configurazione AWS

Il bucket deve già esistere. Policy IAM minima per la chiave:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:AbortMultipartUpload"],
      "Resource": "arn:aws:s3:::NOME-BUCKET/*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::NOME-BUCKET"
    }
  ]
}
```

`s3:ListBucket` serve solo al pulsante "Verifica connessione".

Consigliata sul bucket una regola di ciclo di vita "Abort incomplete multipart uploads" (es. dopo
7 giorni): se l'app viene chiusa a metà di un caricamento, le parti già inviate resterebbero
altrimenti a pagamento.

## Ripristino

Non incluso nell'app. Dalla console AWS o con la CLI:

```bash
aws s3api restore-object --bucket NOME-BUCKET --key CHIAVE \
  --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Bulk"}}'
# dopo 12-48 ore
aws s3 cp s3://NOME-BUCKET/CHIAVE . && tar -xf Cartella_....tar
```
