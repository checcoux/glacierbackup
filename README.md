# Glacier Backup

macOS app (SwiftUI, no external dependencies) that archives folders with `tar` and uploads them to
Amazon S3 in the **Glacier Deep Archive** storage class.

- Each backup creates a full archive: `prefix/Folder/Folder_YYYY-MM-DD_HHMMSS.tar[.gz]`
- The archive is streamed with a multipart upload: no free disk space is needed
- Credentials (Access Key ID + Secret) are stored in the Keychain

## Download

[GlacierBackup.zip (v1.0)](https://bitbucket.org/francescocucchiaro/glacierbackup/raw/v1.0/build/GlacierBackup.zip)
— signed and notarized, for Apple Silicon and Intel Macs running macOS 14 or later.

Unzip it and move `Glacier Backup.app` to the Applications folder.

## Building

```bash
./build.sh                       # creates build/Glacier Backup.app
open "build/Glacier Backup.app"
swift test                       # tests
```

Requires macOS 14+ and Xcode. The project can also be opened in Xcode from `Package.swift`.

## AWS setup

On first launch the app shows a guided setup: it opens the AWS console on a CloudFormation
quick-create page that creates a private bucket and an upload-only access key, then asks you to
paste the stack's `AppConfiguration` output. The template is `Support/cloudformation.yaml`; it
must be hosted on a public S3 URL, set in `SetupLink.templateURL`.

To configure the app by hand instead, use Settings. The bucket must already exist. Minimal IAM
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
