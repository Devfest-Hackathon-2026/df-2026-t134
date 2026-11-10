"""Shared contracts (single source of truth).

- api.py / prompt.py / tts.py / lessons.py: request and response bodies of the learning API
- content.py: teaching material (units, lessons, exercises, answer keys)
- firestore.py: documents that the server writes and the app reads

Change these only in a dedicated contracts PR, then run `make schemas`.
"""
