# S3Archiver

This script compresses, encrypts (optional), and uploads files from a specified base directory to an S3 bucket. It supports multiple compression and encryption methods and includes a dry-run mode for previewing operations.

## Prerequisites

Ensure the following tools are installed:
- `gpg`
- `awscli`
- `zstd`
- `gzip`
- `tar`

You can install these packages using the script's built-in installer or manually:

### Manual Installation
For Debian-based systems:
```bash
sudo apt update && sudo apt install -y gpg awscli zstd gzip tar
```

For RedHat-based systems:
```bash
sudo yum install -y gpg awscli zstd gzip tar
```

## Usage
Run the script with the following options:

### Command-Line Options

| Option               | Description                                                        |
|----------------------|--------------------------------------------------------------------|
| `-b <base_dir>`      | Base directory containing subfolders to process.                  |
| `-o <output_dir>`    | Output directory for temporary files (default: `/tmp/archive_<timestamp>`). |
| `-k <gpg_key>`       | GPG key ID or email for encryption.                               |
| `-e <encryption_type>` | Encryption type: `gpg`, `aes256`, or `none` (default: `gpg`).     |
| `-p <aes_passphrase>` | Passphrase for AES256 encryption.                                |
| `-c <compress_type>`  | Compression type: `zstd`, `tz`, or `none` (default: `zstd`).      |
| `-s <s3_bucket>`      | S3 bucket name for uploads.                                       |
| `-f <s3_folder>`      | Optional S3 folder path.                                          |
| `-a <aws_profile>`    | AWS CLI profile (default: `default`).                            |
| `-l <storage_class>`  | S3 storage class (default: `DEEP_ARCHIVE`).                      |
| `-d`                  | Dry-run mode: Counts folders and archives without processing.    |
| `-h`                  | Show help message.                                               |

### Examples

#### Basic Usage
Compress and encrypt files in `/path/to/base`, then upload to an S3 bucket:
```bash
./script.sh -b /path/to/base -s my-s3-bucket
```

#### Custom Compression and Encryption
Compress using `gzip` and encrypt with AES256:
```bash
./script.sh -b /path/to/base -s my-s3-bucket -c tz -e aes256 -p mypassword
```

#### No Encryption
Skip encryption:
```bash
./S3Archiver.sh -b /mount/storage/Ahoy/ -e none -c none -s backup-bucket -a aws_profile -f Ahoy -o /mount/storage/tmp/archive_$(date +%s)
```

#### Dry Run
Preview the number of folders and archives without processing:
```bash
./script.sh -b /path/to/base -s my-s3-bucket -d
```

## Features
- **Compression**: Supports `zstd`, `gzip`, and no compression.
- **Encryption**: Options for GPG, AES256, or no encryption.
- **S3 Upload**: Automatically uploads files to an S3 bucket, optionally under a specified folder.
- **Threading**: Leverages multithreaded compression for faster performance.
- **Dry Run**: Provides a safe mode to preview operations.

## Notes
- The script requires write permissions for the output directory and AWS credentials configured for the specified profile.
- Ensure the specified GPG key or AES256 passphrase is available for encryption.

