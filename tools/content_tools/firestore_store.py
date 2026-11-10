"""Thin Firestore wrapper (Admin SDK) behind seed.DocumentStore, for the emulator
(no credentials) and for production (Application Default Credentials)."""

import socket
import time
from collections.abc import Sequence

import firebase_admin
from firebase_admin import credentials, firestore
from google.auth.credentials import AnonymousCredentials, Credentials
from google.cloud.firestore import Client

from content_tools.seed import DeleteDocument, SetDocument, Write

# Firestore allows at most 500 writes per batch.
BATCH_SIZE = 500


class _EmulatorCredential(credentials.Base):
    """The emulator needs no Google credentials; the client authenticates as `owner`."""

    def get_credential(self) -> Credentials:
        return AnonymousCredentials()


class FirestoreStore:
    def __init__(self, client: Client) -> None:
        self._client = client

    def list_ids(self, collection: str) -> set[str]:
        return {ref.id for ref in self._client.collection(collection).list_documents()}

    def apply(self, writes: Sequence[Write]) -> None:
        for start in range(0, len(writes), BATCH_SIZE):
            batch = self._client.batch()
            for write in writes[start : start + BATCH_SIZE]:
                ref = self._client.collection(write.collection).document(write.doc_id)
                match write:
                    case SetDocument():
                        batch.set(ref, write.data)
                    case DeleteDocument():
                        batch.delete(ref)
            batch.commit()


def connect_emulator(project_id: str) -> FirestoreStore:
    """Connect to the emulator named by FIRESTORE_EMULATOR_HOST (read by the client library).
    The caller must have checked that the variable is set."""
    app = firebase_admin.initialize_app(
        _EmulatorCredential(), {"projectId": project_id}, name="content-tools"
    )
    return FirestoreStore(firestore.client(app))


def connect_production(project_id: str) -> FirestoreStore:
    """Connect to the real Firestore of project_id with Application Default Credentials.
    The caller must have checked that FIRESTORE_EMULATOR_HOST is not set."""
    app = firebase_admin.initialize_app(
        credentials.ApplicationDefault(), {"projectId": project_id}, name="content-tools-prod"
    )
    return FirestoreStore(firestore.client(app))


def wait_for_emulator(host: str, timeout_seconds: float) -> None:
    """Block until host ("name:port") accepts TCP connections; raise TimeoutError otherwise."""
    name, _, port = host.rpartition(":")
    deadline = time.monotonic() + timeout_seconds
    while True:
        try:
            with socket.create_connection((name, int(port)), timeout=2):
                return
        except OSError as error:
            if time.monotonic() >= deadline:
                raise TimeoutError(
                    f"Firestore emulator at {host} is not reachable after {timeout_seconds:.0f}s"
                ) from error
            time.sleep(1)
