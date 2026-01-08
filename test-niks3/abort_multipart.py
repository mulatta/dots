#!/usr/bin/env nix-shell
#!nix-shell -i python3 -p python3Packages.boto3
"""
Fast R2 multipart upload abort script using boto3 with ThreadPoolExecutor.
"""

import boto3
from botocore.config import Config
from concurrent.futures import ThreadPoolExecutor, as_completed
import os
import sys

# Configuration
BUCKET = "cache"
ACCOUNT_ID = "a36871be6860124304dfb5c3b3eb8c1a"
ENDPOINT = f"https://{ACCOUNT_ID}.r2.cloudflarestorage.com"
MAX_WORKERS = 50

# Credentials from environment or hardcoded for testing
ACCESS_KEY = os.environ.get("AWS_ACCESS_KEY_ID", "e5d78ed7517b1b9df13eedd960f65dfe")
SECRET_KEY = os.environ.get("AWS_SECRET_ACCESS_KEY", "51010687e0053c337a88f17428a79c4380d7abf6ea10638f3834d5413d8a18e0")

def get_client():
    """Create S3 client with connection pooling."""
    config = Config(
        max_pool_connections=MAX_WORKERS,
        retries={'max_attempts': 3}
    )
    return boto3.client(
        's3',
        endpoint_url=ENDPOINT,
        aws_access_key_id=ACCESS_KEY,
        aws_secret_access_key=SECRET_KEY,
        config=config
    )

def abort_upload(client, key, upload_id):
    """Abort a single multipart upload."""
    try:
        client.abort_multipart_upload(
            Bucket=BUCKET,
            Key=key,
            UploadId=upload_id
        )
        return True
    except Exception as e:
        return False

def main():
    print("Aborting incomplete multipart uploads...")

    client = get_client()

    # List all incomplete uploads
    uploads = []
    paginator = client.get_paginator('list_multipart_uploads')

    for page in paginator.paginate(Bucket=BUCKET):
        if 'Uploads' in page:
            for upload in page['Uploads']:
                uploads.append((upload['Key'], upload['UploadId']))

    total = len(uploads)
    print(f"Found {total} incomplete uploads")

    if total == 0:
        print("Nothing to abort")
        return

    print(f"Aborting with {MAX_WORKERS} workers...")

    completed = 0
    failed = 0

    with ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = {
            executor.submit(abort_upload, client, key, upload_id): (key, upload_id)
            for key, upload_id in uploads
        }

        for future in as_completed(futures):
            if future.result():
                completed += 1
            else:
                failed += 1

            done = completed + failed
            if done % 100 == 0 or done == total:
                pct = done * 100 // total
                print(f"\rProgress: {done}/{total} ({pct}%) - OK: {completed}, Failed: {failed}", end="", flush=True)

    print()

    # Verify
    remaining = 0
    for page in paginator.paginate(Bucket=BUCKET):
        if 'Uploads' in page:
            remaining += len(page['Uploads'])

    if remaining == 0:
        print("All incomplete uploads aborted")
    else:
        print(f"Warning: {remaining} remain")

if __name__ == "__main__":
    main()
