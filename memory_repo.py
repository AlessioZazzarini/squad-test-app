"""In-memory implementation of the ItemRepository interface."""
import uuid
from typing import Dict, Optional

from repository import ItemRepository


class MemoryRepository(ItemRepository):

    def __init__(self):
        self._store: Dict[str, dict] = {}

    def add(self, item: dict) -> dict:
        item_id = str(uuid.uuid4())
        record = {"id": item_id, **item}
        self._store[item_id] = record
        return record

    def get(self, item_id: str) -> Optional[dict]:
        return self._store.get(item_id)

    def list_all(self) -> list:
        return list(self._store.values())

    def delete(self, item_id: str) -> bool:
        if item_id in self._store:
            del self._store[item_id]
            return True
        return False
