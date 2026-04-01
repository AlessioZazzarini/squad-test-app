"""Abstract repository interface for item storage."""
from abc import ABC, abstractmethod
from typing import Optional


class ItemRepository(ABC):

    @abstractmethod
    def add(self, item: dict) -> dict:
        ...

    @abstractmethod
    def get(self, item_id: str) -> Optional[dict]:
        ...

    @abstractmethod
    def list_all(self) -> list:
        ...

    @abstractmethod
    def delete(self, item_id: str) -> bool:
        ...
