"""POST /v1/lessons/{lessonId}/complete: finish a lesson after every exercise was attempted."""

from app.schemas.common import Contract, Id, ProgressSnapshot


class CompleteLessonResponse(Contract):
    lesson_id: Id
    progress: ProgressSnapshot
