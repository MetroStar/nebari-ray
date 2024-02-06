from nebari.hookspecs import NebariStage, hookimpl
from typing import List

from .plugin import RayStage

@hookimpl
def nebari_stage() -> List[NebariStage]:
    return [
        RayStage,
    ]
