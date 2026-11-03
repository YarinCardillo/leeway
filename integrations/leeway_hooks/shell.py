"""Split literal shell command boundaries without interpreting data as commands."""

from __future__ import annotations

import shlex

SEPARATORS = frozenset(";&|()\n")


def segments(command: str):
    """Yield literal argv and its following operator, preserving empty scope boundaries."""
    scanner = _Scanner(command)
    while scanner.has_input:
        boundary = scanner.step()
        if boundary is not None:
            raw, operator = boundary
            yield shlex.split(raw), operator
    tokens = shlex.split(scanner.finish())
    if tokens:
        yield tokens, None


class _Scanner:
    def __init__(self, command: str):
        self._source = command
        self._index = 0
        self._quote = None
        self._buffer = []
        self._heredocs = []

    @property
    def has_input(self) -> bool:
        return self._index < len(self._source)

    def step(self) -> tuple[str, str] | None:
        char = self._source[self._index]
        if char == "\\" and self._quote != "'":
            pair = self._source[self._index:self._index + 2]
            if pair != "\\\n":
                self._buffer.append(pair)
            self._index += len(pair)
            return None
        if self._quote:
            if char == self._quote:
                self._quote = None
        elif char in {"'", '"'}:
            self._quote = char
        elif char == "#" and (not self._buffer or self._buffer[-1] in {" ", "\t", "\r"}):
            newline = self._source.find("\n", self._index)
            self._index = len(self._source) if newline < 0 else newline
            return None
        elif char in SEPARATORS:
            return self._boundary(char)
        elif char == "<":
            document = _heredoc(self._source, self._index)
            if document:
                self._heredocs.append(document)
        self._buffer.append(char)
        self._index += 1
        return None

    def finish(self) -> str:
        result = "".join(self._buffer)
        self._buffer.clear()
        return result

    def _boundary(self, char: str) -> tuple[str, str]:
        result = self.finish()
        self._index += 1
        if char in {"&", "|"} and self._source[self._index:self._index + 1] == char:
            self._index += 1
            char += char
        if char == "\n" and self._heredocs:
            self._index = _skip_documents(self._source, self._index, self._heredocs)
            self._heredocs.clear()
        return result, char


def _heredoc(source: str, index: int) -> tuple[str, bool] | None:
    if (not source.startswith("<<", index) or source.startswith("<<<", index)
            or (index and source[index - 1] == "<")):
        return None
    start = index + 2
    strip_tabs = source.startswith("-", start)
    lexer = shlex.shlex(source[start + int(strip_tabs):], posix=True, punctuation_chars=";&|()<>")
    lexer.whitespace_split = True
    delimiter = lexer.get_token()
    if not delimiter:
        raise ValueError("here-document needs a literal delimiter")
    return delimiter, strip_tabs


def _skip_documents(source: str, index: int, documents: list[tuple[str, bool]]) -> int:
    for delimiter, strip_tabs in documents:
        while index < len(source):
            end = source.find("\n", index)
            end = len(source) if end < 0 else end
            line = source[index:end]
            index = min(end + 1, len(source))
            if (line.lstrip("\t") if strip_tabs else line) == delimiter:
                break
        else:
            raise ValueError("unterminated here-document")
    return index
