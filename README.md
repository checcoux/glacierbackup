# Glacier Backup

macOS app (SwiftUI, no external dependencies) that archives folders with `tar` and uploads them to
Amazon S3 in the **Glacier Deep Archive** storage class.

- Each backup creates a full archive: `prefix/Folder/Folder_YYYY-MM-DD_HHMMSS.tar[.gz]`
- The archive is streamed with a multipart upload: no free disk space is needed
- A guided setup creates the bucket and a dedicated access key on your AWS account (new in 1.1)
- Credentials (Access Key ID + Secret) are stored in the Keychain

## Download

[GlacierBackup.zip (v1.0)](https://bitbucket.org/francescocucchiaro/glacierbackup/raw/v1.0/build/GlacierBackup.zip)
— signed and notarized, for Apple Silicon and Intel Macs running macOS 14 or later.

Unzip it and move `Glacier Backup.app` to the Applications folder.

**1.1 beta**, with the guided setup:
[GlacierBackupBeta.zip](https://bitbucket.org/francescocucchiaro/glacierbackup/raw/setup-wizard/build/GlacierBackupBeta.zip)
— signed and notarized. It installs as a separate app, `Glacier Backup Beta`, with its own settings
and credentials, so it can run next to 1.0.

## Building

```bash
./build.sh                       # creates build/Glacier Backup.app
open "build/Glacier Backup.app"
swift test                       # tests
```

Requires macOS 14+ and Xcode. The project can also be opened in Xcode from `Package.swift`.

On any branch other than `main` the script builds `build/Glacier Backup Beta.app` and
`build/GlacierBackupBeta.zip` instead: a separate app with its own bundle identifier, settings and
Keychain item.

To sign with a Developer ID certificate and notarize the build for distribution:

```bash
SIGN_IDENTITY="Developer ID Application: Name (TEAMID)" NOTARY_PROFILE=profile ./build.sh
```

where `profile` was created once with `xcrun notarytool store-credentials`.

## AWS setup

### Guided setup

On first launch, while the app is not configured, a three-step wizard opens. It can be reopened
from Settings → "Configurazione guidata…".

1. **Account** — links to the AWS sign-up page if you do not have an account yet.
2. **Create** — pick a region and open the AWS console on a CloudFormation quick-create page. Tick
   the box that acknowledges the creation of IAM resources, press "Create stack" and wait for
   `CREATE_COMPLETE` (about a minute).
3. **Connect** — open the stack's "Outputs" tab, copy the `AppConfiguration` value and paste it
   into the app. The app checks the connection and configures itself.

The stack creates:

- a private S3 bucket, with a lifecycle rule that removes incomplete multipart uploads after 7 days;
- an IAM user with an access key that can only upload to that bucket.

Deleting the stack does not delete the bucket or the backups in it. The secret access key is
shown in clear text in the stack outputs, to anyone with console access to the account.

The template is `Support/cloudformation.yaml`. CloudFormation only accepts templates hosted on
S3, so a copy is published at the URL in `SetupLink.templateURL` (`Sources/GlacierBackup/Setup.swift`):
upload the file there again whenever it changes.

### Manual setup

Enter region, bucket and access key in Settings. The bucket must already exist. Minimal IAM
policy for the key:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["s3:PutObject", "s3:AbortMultipartUpload"],
      "Resource": "arn:aws:s3:::BUCKET-NAME/*"
    },
    {
      "Effect": "Allow",
      "Action": "s3:ListBucket",
      "Resource": "arn:aws:s3:::BUCKET-NAME"
    }
  ]
}
```

## Restoring

Not included in the app. From the AWS console or with the CLI:

```bash
aws s3api restore-object --bucket BUCKET-NAME --key KEY \
  --restore-request '{"Days":7,"GlacierJobParameters":{"Tier":"Bulk"}}'
# after 12-48 hours
aws s3 cp s3://BUCKET-NAME/KEY . && tar -xf Folder_....tar
```
