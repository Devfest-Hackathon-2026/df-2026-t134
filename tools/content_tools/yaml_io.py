"""Strict YAML reading: safe types only, and duplicate keys are an error instead of last-wins."""

from pathlib import Path

import yaml


class _StrictLoader(yaml.SafeLoader):
    pass


def _construct_mapping(loader: _StrictLoader, node: yaml.MappingNode) -> dict[object, object]:
    loader.flatten_mapping(node)
    mapping: dict[object, object] = {}
    for key_node, value_node in node.value:
        key = loader.construct_object(key_node, deep=True)
        if key in mapping:
            raise yaml.constructor.ConstructorError(
                "while constructing a mapping",
                node.start_mark,
                f"found duplicate key {key!r}",
                key_node.start_mark,
            )
        mapping[key] = loader.construct_object(value_node, deep=True)
    return mapping


_StrictLoader.add_constructor(yaml.resolver.BaseResolver.DEFAULT_MAPPING_TAG, _construct_mapping)


class YamlError(Exception):
    """The file is not readable YAML (syntax error or duplicate key)."""


def read_yaml(path: Path) -> object:
    try:
        # _StrictLoader is a SafeLoader: no arbitrary Python objects.
        return yaml.load(path.read_text(encoding="utf-8"), Loader=_StrictLoader)
    except yaml.YAMLError as error:
        raise YamlError(str(error)) from error
