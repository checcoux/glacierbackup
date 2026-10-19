# Glacier Backup

macOS app (SwiftUI, no external dependencies) that archives folders with `tar` and uploads them to
Amazon S3 in the **Glacier Deep Archive** storage class.

- Each backup creates a full archive: `prefix/Folder/Folder_YYYY-MM-DD_HHMMSS.tar[.gz]`
- The archive is streamed with a multipart upload: no free disk space is needed
- Credentials (Access Key ID + Secret) are stored in the Keychain

## Download

You can download [the latest release](https://github.com/checcoux/glacierbackup/releases)  - signed and notarized, for Apple Silicon and Intel Macs running macOS 14 or later.

Unzip it and move `Glacier Backup.app` to the Applications folder.

## Building

```bash
./build.sh                       # creates build/Glacier Backup.app
open "build/Glacier Backup.app"
swift test                       # tests
```

Requires macOS 14+ and Xcode. The project can also be opened in Xcode from `Package.swift`.

## AWS setup

The bucket must already exist. Minimal IAM policy for the key:

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
