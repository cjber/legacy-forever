#!/usr/bin/env python3
"""Reject implicit select() expansion in Lua 5.1 calls, tables and returns."""

import argparse
import re
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class Token:
    value: str
    line: int
    end_line: int
    kind: str = "symbol"


class LuaSyntaxError(ValueError):
    pass


LONG_OPEN = re.compile(r"\[(=*)\[")
NUMBER = re.compile(r"(?:0[xX][0-9a-fA-F]+|(?:\d+(?:\.(?!\.)\d*)?|\.\d+)(?:[eE][+-]?\d+)?)")
NAME = re.compile(r"[a-zA-Z_][a-zA-Z_0-9]*")
ALLOW = re.compile(r"--\s*multi-value:\s*\S")


def tokenize(source: str) -> tuple[list[Token], set[int]]:
    tokens = []
    allowed = set()
    pos, line = 0, 1
    while pos < len(source):
        start, first_line = pos, line
        char = source[pos]
        if char.isspace():
            line += char == "\n"
            pos += 1
            continue
        comment = source.startswith("--", pos)
        content = pos + 2 if comment else pos
        long = LONG_OPEN.match(source, content)
        if long:
            closing = "]" + long[1] + "]"
            end = source.find(closing, long.end())
            if end < 0:
                raise LuaSyntaxError(f"{line}: unterminated long string/comment")
            pos = end + len(closing)
            kind = "string"
        elif comment:
            end = source.find("\n", pos)
            pos = end if end >= 0 else len(source)
            # Only an actual trailing line comment can authorize expansion, never string contents.
            if tokens and tokens[-1].end_line == line and ALLOW.match(source[start:pos]):
                allowed.add(line)
            continue
        elif char in "\"'":
            pos += 1
            while pos < len(source) and source[pos] != char:
                if source[pos] == "\n":
                    raise LuaSyntaxError(f"{line}: newline in quoted string")
                if source[pos] == "\\":
                    pos += 1
                    if source[pos : pos + 2] == "\r\n":
                        pos += 1
                pos += 1
            if pos >= len(source):
                raise LuaSyntaxError(f"{line}: unterminated quoted string")
            pos += 1
            kind = "string"
        elif number := NUMBER.match(source, pos):
            pos = number.end()
            kind = "number"
        elif name := NAME.match(source, pos):
            pos = name.end()
            kind = "name"
        else:
            symbol = next((s for s in ("...", "..", "==", "~=", "<=", ">=") if source.startswith(s, pos)), char)
            if symbol == char and char not in "+-*/%^#=<>;:,().{}[]":
                raise LuaSyntaxError(f"{line}: unexpected character {char!r}")
            pos += len(symbol)
            kind = "symbol"
        line += source.count("\n", start, pos)
        if not comment:
            tokens.append(Token(source[start:pos], first_line, line, kind))
    tokens.append(Token("<eof>", line, line))
    return tokens, allowed


# Right-associative concatenation/power and unary precedence matter: select(...) + 1 is scalar.
PRECEDENCE = {
    "or": 1,
    "and": 2,
    "<": 3,
    ">": 3,
    "<=": 3,
    ">=": 3,
    "~=": 3,
    "==": 3,
    "..": 4,
    "+": 5,
    "-": 5,
    "*": 6,
    "/": 6,
    "%": 6,
    "^": 8,
}
BLOCK_END = {"end", "else", "elseif", "until", "<eof>"}


class Parser:
    """Walk the grammar so nested calls and function bodies keep their own expression lists."""

    def __init__(self, source: str):
        self.tokens, self.allowed = tokenize(source)
        self.pos = 0
        self.findings: list[tuple[int, str]] = []

    @property
    def current(self) -> Token:
        return self.tokens[self.pos]

    def take(self, value: str | None = None) -> Token:
        token = self.current
        if value is not None and token.value != value:
            raise LuaSyntaxError(f"{token.line}: expected {value!r}, got {token.value!r}")
        if token.value == "<eof>":
            raise LuaSyntaxError(f"{token.line}: unexpected end of file")
        self.pos += 1
        return token

    def accept(self, value: str) -> bool:
        if self.current.value != value:
            return False
        self.take()
        return True

    def report(self, select: Token | None, end: Token, context: str) -> None:
        if select and not ({select.end_line, end.end_line} & self.allowed):
            self.findings.append(
                (select.line, f"multi-value: last {context} expands select(); parenthesize or explain")
            )

    def expressions(self) -> Token | None:
        last = self.expression()
        while self.accept(","):
            last = self.expression()
        return last

    def expression(self, minimum: int = 0) -> Token | None:
        if self.current.value in {"not", "-", "#"}:
            self.take()
            self.expression(7)
            select = None
        else:
            select = self.primary()
        while (precedence := PRECEDENCE.get(self.current.value, -1)) >= minimum:
            operator = self.take().value
            self.expression(precedence if operator in {"..", "^"} else precedence + 1)
            select = None
        return select

    def primary(self) -> Token | None:
        token = self.current
        name = None
        select = None
        if self.accept("("):
            self.expression()
            self.take(")")
        elif token.value == "{":
            self.table()
        elif self.accept("function"):
            self.function_body()
        elif token.kind in {"string", "number", "name"} or token.value == "...":
            self.take()
            name = token.value
        else:
            raise LuaSyntaxError(f"{token.line}: expected expression, got {token.value!r}")
        while True:
            if self.accept("."):
                self.take()
                name, select = None, None
            elif self.accept("["):
                self.expression()
                self.take("]")
                name, select = None, None
            elif self.accept(":"):
                self.take()
                self.arguments()
                name, select = None, None
            elif self.current.value in {"(", "{"} or self.current.kind == "string":
                end = self.arguments()
                select = Token("select", token.line, end.end_line) if name == "select" else None
                name = None
            else:
                return select

    def arguments(self) -> Token:
        if self.accept("("):
            last = None if self.current.value == ")" else self.expressions()
            end = self.take(")")
            self.report(last, end, "call argument")
            return end
        if self.current.value == "{":
            return self.table()
        if self.current.kind != "string":
            raise LuaSyntaxError(f"{self.current.line}: expected call arguments")
        return self.take()

    def table(self) -> Token:
        self.take("{")
        last = None
        while self.current.value != "}":
            if self.accept("["):
                self.expression()
                self.take("]")
                self.take("=")
                self.expression()
                last = None
            elif self.current.kind == "name" and self.tokens[self.pos + 1].value == "=":
                self.take()
                self.take("=")
                self.expression()
                last = None
            else:
                last = self.expression()
            if not (self.accept(",") or self.accept(";")):
                break
        end = self.take("}")
        self.report(last, end, "table element")
        return end

    def function_body(self) -> None:
        self.take("(")
        if self.current.value != ")":
            self.take()
            while self.accept(","):
                self.take()
        self.take(")")
        self.block()
        self.take("end")

    def block(self) -> None:
        while self.current.value not in BLOCK_END:
            if self.accept(";") or self.accept("break"):
                continue
            if self.accept("return"):
                if self.current.value not in BLOCK_END | {";"}:
                    last = self.expressions()
                    self.report(last, self.tokens[self.pos - 1], "return expression")
                self.accept(";")
            elif self.accept("if"):
                self.expression()
                self.take("then")
                self.block()
                while self.accept("elseif"):
                    self.expression()
                    self.take("then")
                    self.block()
                if self.accept("else"):
                    self.block()
                self.take("end")
            elif self.accept("while"):
                self.expression()
                self.take("do")
                self.block()
                self.take("end")
            elif self.accept("repeat"):
                self.block()
                self.take("until")
                self.expression()
            elif self.accept("for"):
                self.take()
                while self.accept(","):
                    self.take()
                if not self.accept("="):
                    self.take("in")
                self.expressions()
                self.take("do")
                self.block()
                self.take("end")
            elif self.accept("do"):
                self.block()
                self.take("end")
            elif self.accept("function"):
                self.take()
                while self.accept(".") or self.accept(":"):
                    self.take()
                self.function_body()
            elif self.accept("local"):
                if self.accept("function"):
                    self.take()
                    self.function_body()
                else:
                    self.take()
                    while self.accept(","):
                        self.take()
                    if self.accept("="):
                        self.expressions()
            else:
                self.expressions()
                if self.accept("="):
                    self.expressions()

    def check(self) -> list[tuple[int, str]]:
        self.block()
        if self.current.value != "<eof>":
            raise LuaSyntaxError(f"{self.current.line}: unexpected {self.current.value!r}")
        return sorted(self.findings)


def lua_files(paths: list[Path]) -> list[Path]:
    # Match the runtime gate's exclusions, but include tests and local declarations for this lint.
    excluded = {".git", ".types", ".sift", ".release", ".cache"}
    return sorted(
        {
            file
            for path in paths
            for file in (path.rglob("*.lua") if path.is_dir() else [path])
            if not excluded.intersection(file.parts)
        }
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*", type=Path, default=[Path(".")])
    files = lua_files(parser.parse_args().paths)
    failed = False
    for path in files:
        try:
            for line, message in Parser(path.read_text()).check():
                print(f"{path}:{line}: {message}")
                failed = True
        except (OSError, LuaSyntaxError) as error:
            print(f"{path}:{error}")
            failed = True
    if not failed:
        print(f"Multi-value lint: {len(files)} Lua files checked")
    return int(failed)


if __name__ == "__main__":
    raise SystemExit(main())
