#!/bin/bash

# Default Variables
BASE_DIR="" # Will be set via CLI
OUTPUT_BASE_DIR="/tmp/archive_$(date +%s)" # Default output directory
GPG_KEY="" # GPG key for file encryption
EMAIL_GPG_KEY="" # GPG key for email encryption
ARCHIVE_SUFFIX=".tar.zst.gpg" # Default suffix
COMPRESS_TYPE="zstd" # Compression type (zstd/tz/none)
ENCRYPTION_TYPE="gpg" # Encryption type (gpg/aes256/none)
S3_BUCKET="" # S3 bucket name
S3_FOLDER="" # Optional S3 folder name
AWS_PROFILE="default" # AWS profile name
STORAGE_CLASS="DEEP_ARCHIVE" # Default storage class
DRY_RUN=false # Default to false
EMAIL_RECIPIENT="" # Email recipient for notifications
NOTIFY_ON="always" # Notification type (always/success/failure)

# Install required packages function
install_packages() {
    if [[ -x "$(command -v apt)" ]]; then
        sudo apt update && sudo apt install -y gpg awscli zstd gzip tar mailutils
    elif [[ -x "$(command -v yum)" ]]; then
        sudo yum install -y gpg awscli zstd gzip tar mailx
    else
        echo "Unsupported package manager. Install gpg, awscli, zstd, gzip, tar, and mailutils/mailx manually."
        exit 1
    fi
}

# Display help message
show_help() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -b <base_dir>          Base directory containing subfolders"
    echo "  -o <output_dir>        Output directory for temporary files"
    echo "  -k <gpg_key>           GPG key ID or email for file encryption"
    echo "  -e <encryption_type>   Encryption type: gpg, aes256, none"
    echo "  -p <aes_passphrase>    Passphrase for AES256 encryption"
    echo "  -c <compress_type>     Compression type: zstd, tz, none"
    echo "  -s <s3_bucket>         S3 bucket name"
    echo "  -f <s3_folder>         S3 folder path (optional)"
    echo "  -a <aws_profile>       AWS CLI profile"
    echo "  -l <storage_class>     S3 storage class"
    echo "  -d                     Dry run (counts folders and archives without processing)"
    echo "  -r <email_recipient>   Email recipient for notifications"
    echo "  -g <email_gpg_key>     GPG key ID for email encryption"
    echo "  -n <notify_on>         Notification type: always, success, failure"
    echo "  -h                     Show this help message"
}

# Parse CLI options
while getopts "b:o:k:e:p:c:s:f:a:l:r:g:n:dh" opt; do
    case $opt in
        b) BASE_DIR="$OPTARG" ;;
        o) OUTPUT_BASE_DIR="$OPTARG" ;;
        k) GPG_KEY="$OPTARG" ;;
        e) ENCRYPTION_TYPE="$OPTARG" ;;
        p) AES_PASSPHRASE="$OPTARG" ;;
        c) COMPRESS_TYPE="$OPTARG" ;;
        s) S3_BUCKET="$OPTARG" ;;
        f) S3_FOLDER="$OPTARG" ;;
        a) AWS_PROFILE="$OPTARG" ;;
        l) STORAGE_CLASS="$OPTARG" ;;
        r) EMAIL_RECIPIENT="$OPTARG" ;;
        g) EMAIL_GPG_KEY="$OPTARG" ;;
        n) NOTIFY_ON="$OPTARG" ;;
        d) DRY_RUN=true ;;
        h) show_help; exit 0 ;;
        *) show_help; exit 1 ;;
    esac
done

# Validate required parameters
if [[ -z "$BASE_DIR" || -z "$S3_BUCKET" || -z "$EMAIL_RECIPIENT" || -z "$EMAIL_GPG_KEY" ]]; then
    echo "Error: Base directory, S3 bucket, email recipient, and email GPG key are required."
    show_help
    exit 1
fi

# Set S3 path with optional folder
if [[ -n "$S3_FOLDER" ]]; then
    S3_BUCKET="s3://$S3_BUCKET/$S3_FOLDER"
else
    S3_BUCKET="s3://$S3_BUCKET"
fi

# Initialize notification content
NOTIFICATION_CONTENT="Task Summary:\n"
STATUS="success"

# Dry run logic
if $DRY_RUN; then
    echo "Performing dry run..."
    folder_count=0
    archive_count=0

    while read -r folder; do
        ((folder_count++))
        file_count=$(find "$folder" -maxdepth 1 -type f | wc -l)
        if [[ $file_count -gt 0 ]]; then
            ((archive_count++))
        fi
    done < <(find "$BASE_DIR" -type d)

    echo "Dry run complete:"
    echo "Folders processed: $folder_count"
    echo "Archives to be created: $archive_count"
    NOTIFICATION_CONTENT+="Dry run complete:\nFolders processed: $folder_count\nArchives to be created: $archive_count\n"
    STATUS="success"
    send_notification
    exit 0
fi

# Send notification function
send_notification() {
    echo "$NOTIFICATION_CONTENT" | gpg --encrypt --armour --recipient "$EMAIL_GPG_KEY" | mail -s "S3 Archiver Notification" "$EMAIL_RECIPIENT"
}

# Compress and encrypt function
process_folder() {
    local folder="$1"
    echo "Processing folder: $folder"
    NOTIFICATION_CONTENT+="Processing folder: $folder\n"

    # Find all files in the current folder
    files=$(find "$folder" -maxdepth 1 -type f -print0)
    if [[ -z "$files" ]]; then
        echo "No files found in $folder. Skipping."
        NOTIFICATION_CONTENT+="No files found in $folder. Skipping.\n"
        return
    fi

    # Determine output folder
    relative_path="${folder#$BASE_DIR}" # Remove BASE_DIR from folder path
    relative_path="/${relative_path#/}" # Ensure leading slash is correct
    output_folder="$OUTPUT_BASE_DIR$relative_path"
    mkdir -p "$output_folder"

    # Create a temporary file list
    file_list=$(mktemp)
    find "$folder" -maxdepth 1 -type f -print0 > "$file_list"

    # Determine archive name and compression
    archive_name="$output_folder/${relative_path##*/}"
    case "$COMPRESS_TYPE" in
        zstd) archive_name+=".tar.zst"; tar --zstd -cf "$archive_name" --null --files-from="$file_list" ;;
        tz) archive_name+=".tar.gz"; tar -czf "$archive_name" --null --files-from="$file_list" ;;
        none) archive_name+=".tar"; tar -cf "$archive_name" --null --files-from="$file_list" ;;
        *) echo "Error: Unsupported compression type: $COMPRESS_TYPE"; STATUS="failure"; exit 1 ;;
    esac

    rm -f "$file_list"

    case "$ENCRYPTION_TYPE" in
        gpg)
            if [[ -z "$GPG_KEY" ]]; then
                echo "Error: GPG key is required for GPG encryption."
                STATUS="failure"
                exit 1
            fi
            gpg --output "$archive_name.gpg" --encrypt --recipient "$GPG_KEY" "$archive_name"
            rm -f "$archive_name"
            archive_name+=".gpg"
            ;;
        aes256)
            if [[ -z "$AES_PASSPHRASE" ]]; then
                echo "Error: AES passphrase is required for AES256 encryption."
                STATUS="failure"
                exit 1
            fi
            openssl enc -aes-256-cbc -salt -in "$archive_name" -out "$archive_name.enc" -k "$AES_PASSPHRASE"
            rm -f "$archive_name"
            archive_name+=".enc"
            ;;
        none)
            echo "Skipping encryption for $archive_name."
            ;;
        *)
            echo "Error: Unsupported encryption type: $ENCRYPTION_TYPE"
            STATUS="failure"
            exit 1
            ;;
esac

    # Ensure folder structure in S3
    s3_path="$S3_BUCKET$relative_path/"

    # Upload to S3
    echo "Uploading $archive_name to $s3_path..."
    aws s3 cp "$archive_name" "$s3_path" --profile "$AWS_PROFILE" --storage-class "$STORAGE_CLASS"
    if [[ $? -ne 0 ]]; then
        echo "Error: Upload failed for $archive_name."
        NOTIFICATION_CONTENT+="Error: Upload failed for $archive_name.\n"
        STATUS="failure"
        exit 1
    fi

    # Remove uploaded file
    rm -f "$archive_name"
    echo "$archive_name uploaded and deleted locally."
    NOTIFICATION_CONTENT+="$archive_name uploaded and deleted locally.\n"
}

# Recursively process each subfolder
find "$BASE_DIR" -type d | while read -r folder; do
    process_folder "$folder"
    if [[ $? -ne 0 ]]; then
        STATUS="failure"
    fi
done

# Notification logic
if [[ "$NOTIFY_ON" == "always" || ("$NOTIFY_ON" == "success" && "$STATUS" == "success") || ("$NOTIFY_ON" == "failure" && "$STATUS" == "failure") ]]; then
    send_notification
fi

echo "All folders processed."
