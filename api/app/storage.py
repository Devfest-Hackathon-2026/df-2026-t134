"""The only module that writes to Cloud Storage (Firebase Storage bucket).

Clients read audio/ and images/ directly with their Firebase login (firebase/storage.rules) and
can never upload; the server and the content tools write them with Google credentials.
"""

from typing import Protocol

import firebase_admin
from firebase_admin import storage
from google.cloud.storage import Bucket

# Audio and image paths are content hashes, so a file never changes once written.
IMMUTABLE_CACHE_CONTROL = "private, max-age=31536000, immutable"


class AudioStore(Protocol):
    def exists(self, path: str) -> bool: ...

    def put(self, path: str, data: bytes, content_type: str) -> None: ...


def firebase_bucket(firebase_app: firebase_admin.App, bucket_name: str) -> Bucket:
    return storage.bucket(bucket_name, app=firebase_app)


class BucketAudioStore:
    def __init__(self, bucket: Bucket) -> None:
        self._bucket = bucket

    def exists(self, path: str) -> bool:
        return self._bucket.blob(path).exists()

    def put(self, path: str, data: bytes, content_type: str) -> None:
        if not path.startswith("audio/"):
            raise ValueError("audio must be stored under audio/ (the only path clients read)")
        blob = self._bucket.blob(path)
        blob.cache_control = IMMUTABLE_CACHE_CONTROL
        blob.upload_from_string(data, content_type=content_type)


class BucketImageStore:
    """Story illustrations made by the content tools (`make illustrate`)."""

    def __init__(self, bucket: Bucket) -> None:
        self._bucket = bucket

    def exists(self, path: str) -> bool:
        return self._bucket.blob(path).exists()

    def put(self, path: str, data: bytes, content_type: str) -> None:
        if not path.startswith("images/"):
            raise ValueError("images must be stored under images/ (the only path clients read)")
        if not content_type.startswith("image/"):
            raise ValueError("content_type must be an image type")
        blob = self._bucket.blob(path)
        blob.cache_control = IMMUTABLE_CACHE_CONTROL
        blob.upload_from_string(data, content_type=content_type)
