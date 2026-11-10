"""Fixtures for the Firestore emulator suite (`make check-api-integration`).

The make target starts an emulator without published ports and seeds content/ with the tools
service first, so these tests read the real Unit 1 documents. Every test uses a fresh uid,
so the suite needs no cleanup and can run against an emulator that is in use.
"""

import os
import time
import urllib.error
import urllib.request
import uuid
from collections.abc import Iterator

import firebase_admin
import pytest
from firebase_admin import credentials
from google.auth.credentials import AnonymousCredentials
from google.cloud.firestore import Client

from app.repo.firestore import FirestoreLearningRepo, emulator_firestore_client
from tests_integration.support import SEEDED_LESSON_ID

EMULATOR_WAIT_SECONDS = 60


class _OfflineCredential(credentials.Base):
    def get_credential(self) -> AnonymousCredentials:
        return AnonymousCredentials()


def _required_env(name: str) -> str:
    value = os.environ.get(name, "").strip()
    if not value:
        pytest.fail(f"{name} is not set: run this suite with `make check-api-integration`")
    return value


def _wait_for_emulator(host: str) -> None:
    deadline = time.monotonic() + EMULATOR_WAIT_SECONDS
    while True:
        try:
            with urllib.request.urlopen(f"http://{host}/", timeout=2) as response:
                if response.status == 200:
                    return
        except (urllib.error.URLError, OSError):
            pass
        if time.monotonic() >= deadline:
            pytest.fail(f"Firestore emulator at {host} is not reachable")
        time.sleep(1)


@pytest.fixture(scope="session")
def firestore_client() -> Iterator[Client]:
    _wait_for_emulator(_required_env("FIRESTORE_EMULATOR_HOST"))
    project_id = _required_env("FIREBASE_PROJECT_ID")
    app = firebase_admin.initialize_app(
        _OfflineCredential(), options={"projectId": project_id}, name=f"it-{uuid.uuid4().hex}"
    )
    yield emulator_firestore_client(app)
    firebase_admin.delete_app(app)


@pytest.fixture(scope="session")
def repo(firestore_client: Client) -> FirestoreLearningRepo:
    repo = FirestoreLearningRepo(firestore_client)
    if repo.get_lesson(SEEDED_LESSON_ID) is None:
        pytest.fail(f"lesson {SEEDED_LESSON_ID} is not in the emulator: seed content/ first")
    return repo


@pytest.fixture
def uid() -> str:
    return f"it-{uuid.uuid4().hex}"
