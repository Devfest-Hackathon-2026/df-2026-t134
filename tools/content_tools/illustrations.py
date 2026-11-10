"""Story scene pictures, generated once with a Gemini image model (`make illustrate`).

Every `illustration.prompt` of the story scenes (exercise scenes and the outcome scenes of the
answer keys) is drawn with one shared style, stored in Cloud Storage as
images/scenes/<hash of model and full prompt>.jpg (so a rerun generates nothing new), and
listed in content/images/scenes.yaml. `seed` fills Illustration.imagePath from that file, so
the YAML under content/units/ never carries generated paths (validation rejects one written by
hand).
"""

import hashlib
import time
from collections.abc import Callable, Iterable, Mapping, Sequence
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated, Protocol, Self

import yaml
from app.ai import AiBlocked, AiUnavailable
from app.ai.image import GeneratedImage, ImageGenerator, ImageRateLimited
from app.schemas.common import Contract, NonEmptyText
from app.schemas.content import Scene
from pydantic import Field, StringConstraints, ValidationError, model_validator

from content_tools.loader import Content, Problem
from content_tools.scenes import all_scenes, map_scenes
from content_tools.yaml_io import YamlError, read_yaml

SCENES_IMAGE_PREFIX = "images/scenes/"
IMAGE_EXTENSION = ".jpg"
ILLUSTRATIONS_FILE = Path("images") / "scenes.yaml"
# Hard cap on new pictures per run (the hackathon budget); cached pictures do not count.
DEFAULT_MAX_NEW_IMAGES = 30
# Pauses before asking again when the quota is used up for the moment (HTTP 429).
RATE_LIMIT_WAITS_SECONDS = (20.0, 40.0, 60.0, 60.0, 90.0)

# Put before every scene prompt so all pictures look like one picture book.
STYLE_PROMPT = """\
A warm, soft watercolor illustration for a Japanese picture book for junior high school \
students. Gentle hand-drawn lines, soft paper texture, calm and friendly mood. Palette: \
ivory and cream backgrounds, terracotta, soft peach, warm beige, muted olive and a little \
dusty blue. Simple, uncluttered composition with one clear moment, eye level, medium shot.

Recurring original characters (draw them the same way every time they appear):
- Yui: a 14-year-old Japanese girl in 8th grade, shoulder-length black hair with a small \
terracotta hair clip, round friendly eyes, cream cardigan over a navy school uniform.
- Sota: her classmate, a 14-year-old Japanese boy, short slightly messy black hair, light \
blue hoodie over a white shirt, cheerful.
- The teacher: a kind Japanese woman in her forties, short brown hair, round glasses, \
mustard cardigan.
- The AI assistant: a small friendly tablet character whose screen shows a softly glowing \
round face with two dot eyes and a small smile, giving off a warm light.

Rules: no text, letters, numbers, writing, signs, logos or speech bubbles anywhere in the \
picture (screens and paper show only soft shapes). No real brands, products or real people. \
Wholesome and age-appropriate.

Scene: """

SceneImagePath = Annotated[str, StringConstraints(pattern=r"^images/scenes/[0-9a-f]{64}\.jpg$")]

HEADER = """\
# `make illustrate` が書き出すファイル（手で編集しない）。
# 紙しばいの場面の絵の説明（prompt）と、その画像の保存先。
# `make seed` がこの対応表から教材の illustration.imagePath を埋める。
"""


def full_prompt(prompt: str) -> str:
    return STYLE_PROMPT + prompt.strip()


def image_path(model: str, prompt: str) -> str:
    """Storage path of the picture of prompt (in the shared style) drawn by model."""
    digest = hashlib.sha256(f"{model}\n{full_prompt(prompt)}".encode()).hexdigest()
    return f"{SCENES_IMAGE_PREFIX}{digest}{IMAGE_EXTENSION}"


class SceneImage(Contract):
    prompt: NonEmptyText
    image_path: SceneImagePath


class SceneImagesFile(Contract):
    images: list[SceneImage] = Field(default_factory=list)

    @model_validator(mode="after")
    def _unique_prompts(self) -> Self:
        prompts = [image.prompt for image in self.images]
        if len(set(prompts)) != len(prompts):
            raise ValueError("each prompt must appear once")
        return self

    def paths_by_prompt(self) -> dict[str, str]:
        return {image.prompt: image.image_path for image in self.images}


def hand_written_image_paths(content: Content) -> list[Problem]:
    return [
        Problem(
            located.path,
            f"{located.where}: illustration.imagePath is filled in from {ILLUSTRATIONS_FILE} "
            "by `make illustrate`; remove it",
        )
        for located in all_scenes(content)
        if located.scene.illustration is not None
        and located.scene.illustration.image_path is not None
    ]


def unique_prompts(content: Content) -> list[str]:
    """Every illustration prompt once, in file order."""
    return list(
        dict.fromkeys(
            located.scene.illustration.prompt
            for located in all_scenes(content)
            if located.scene.illustration is not None
        )
    )


def read_scene_images(root: Path) -> tuple[SceneImagesFile, list[Problem]]:
    """root/images/scenes.yaml, or an empty file when it does not exist yet."""
    path = root / ILLUSTRATIONS_FILE
    if not path.exists():
        return SceneImagesFile(), []
    try:
        return SceneImagesFile.model_validate(read_yaml(path)), []
    except (YamlError, ValidationError) as error:
        return SceneImagesFile(), [Problem(path, str(error))]


def write_scene_images(root: Path, images: Iterable[SceneImage]) -> Path:
    path = root / ILLUSTRATIONS_FILE
    document = SceneImagesFile(images=list(images))
    body = yaml.safe_dump(
        document.model_dump(mode="json"), allow_unicode=True, sort_keys=False, width=1000
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(HEADER + body, encoding="utf-8")
    return path


def with_images(content: Content, paths_by_prompt: Mapping[str, str]) -> Content:
    """Content whose illustrations carry the picture of their prompt, when it has one (a scene
    without a picture yet is shown with the app's placeholder)."""

    def scene(item: Scene) -> Scene:
        illustration = item.illustration
        if illustration is None or illustration.prompt not in paths_by_prompt:
            return item
        drawn = illustration.model_copy(update={"image_path": paths_by_prompt[illustration.prompt]})
        return item.model_copy(update={"illustration": drawn})

    return map_scenes(content, scene)


class ImageStore(Protocol):
    def exists(self, path: str) -> bool: ...

    def put(self, path: str, data: bytes, content_type: str) -> None: ...


class BudgetExhausted(Exception):
    """The run already generated its maximum number of new pictures."""


class CachedIllustrator:
    """The stored picture of a prompt, else a new one from the model (at most max_new
    requests per run), which is stored for the next time. When the quota is used up for the
    moment, it waits and asks again (those answers generate nothing and are not counted)."""

    def __init__(
        self,
        store: ImageStore,
        generator: ImageGenerator,
        max_new: int,
        waits: Sequence[float] = RATE_LIMIT_WAITS_SECONDS,
        sleep: Callable[[float], None] = time.sleep,
    ) -> None:
        if max_new < 0:
            raise ValueError("max_new must not be negative")
        self._store = store
        self._generator = generator
        self._max_new = max_new
        self._waits = tuple(waits)
        self._sleep = sleep
        self.requested = 0  # requests that may be billed (everything but 429)
        self.generated = 0  # pictures stored

    def image_path_for(self, prompt: str) -> str:
        """Raises BudgetExhausted, AiUnavailable or AiBlocked when there is no picture."""
        path = image_path(self._generator.model, prompt)
        if self._store.exists(path):
            return path
        if self.requested >= self._max_new:
            raise BudgetExhausted(f"already made {self.requested} image request(s)")
        image = self._generate(full_prompt(prompt))
        if image.mime_type != "image/jpeg":
            raise AiUnavailable(f"the image model returned {image.mime_type}, not image/jpeg")
        self._store.put(path, image.data, image.mime_type)
        self.generated += 1
        return path

    def _generate(self, prompt: str) -> GeneratedImage:
        for wait in (*self._waits, None):
            try:
                self.requested += 1  # counted before the call: a failed call may be billed
                return self._generator.generate(prompt)
            except ImageRateLimited:
                self.requested -= 1  # a 429 generates (and bills) nothing
                if wait is None:
                    raise
                self._sleep(wait)
        raise AssertionError("unreachable")


@dataclass(frozen=True)
class Missing:
    prompt: str
    reason: str


class Illustrator(Protocol):
    def image_path_for(self, prompt: str) -> str: ...


def illustrate(
    illustrator: Illustrator, prompts: Iterable[str]
) -> tuple[list[SceneImage], list[Missing]]:
    """A picture for every prompt, and the prompts without one (to run again)."""
    drawn: list[SceneImage] = []
    missing: list[Missing] = []
    for prompt in prompts:
        try:
            drawn.append(SceneImage(prompt=prompt, image_path=illustrator.image_path_for(prompt)))
        except (AiUnavailable, AiBlocked, BudgetExhausted) as error:
            missing.append(Missing(prompt, f"{type(error).__name__}: {error}"))
    return drawn, missing
