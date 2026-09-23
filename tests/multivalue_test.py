"""Regressions for Lua expansion contexts, lexical boundaries and explicit intent."""

import unittest

from tools.lint_multivalue import LuaSyntaxError, Parser


class MultiValueTests(unittest.TestCase):
    def test_expanding_contexts(self):
        for source in [
            "f(select(2, UnitClass(u)))",
            "f(a, select(2, g()))",
            "obj:method(select(2, g()))",
            "local t = {1, select(2, g())}",
            "local t = {select(2, g()),}",
            "local t = {select(2, g());}",
            "return a, select(2, g())",
            "function f() return select(2, g()) end",
            "local f = function() return select(2, g()) end",
            "f(function() return select(2, g()) end)",
            "return (function() return select(2, g()) end)()",
            "return select(2, g()) -- multi-value:",
            "return select(2, g()) --[=[ multi-value: not a line comment ]=]",
            'return select(2, g()) .. "scalar" , select(2, g())',
        ]:
            with self.subTest(source=source):
                self.assertEqual(len(Parser(source).check()), 1)

    def test_scalar_or_intentional_contexts(self):
        for source in [
            "f((select(2, g())))",
            "f(select(2, g()), x)",
            "local t = {(select(2, g()))}",
            "local t = {select(2, g()), x}",
            "local t = {key = select(2, g())}",
            "local t = {[select(2, g())] = select(2, g())}",
            "local t = {select(2, g()), key = 1}",
            "return (select(2, g()))",
            "return select(2, g()), x",
            "return select(2, g()) + 1",
            "return 1 + select(2, g())",
            "return -select(2, g())",
            "return select(2, g()) or 1",
            "return select(2, g()).field",
            "return select(2, g())[1]",
            "return select(2, g())()",
            "local x, y = select(2, g())",
            "x, y = select(2, g())",
            "f(object.select(2, g()))",
            "f(object:select(2, g()))",
            "local function select(a, b) return a, b end",
            "f(select(2, g())) -- multi-value: forward all return values",
            "local t = {select(2, g())} -- multi-value: collect the tail",
            "return select(2, g()) -- multi-value: preserve the remaining values",
            "f(\n select(2, g()) -- multi-value: forward the tail\n)",
        ]:
            with self.subTest(source=source):
                self.assertEqual(Parser(source).check(), [])

    def test_nested_calls_are_independent(self):
        self.assertEqual(len(Parser("f(select(2, select(3, g())))").check()), 2)
        self.assertEqual(len(Parser("f((select(2, h(select(2, g())))))").check()), 1)
        self.assertEqual(len(Parser("local t = {key = f(select(2, g()))}").check()), 1)

    def test_strings_comments_and_line_numbers(self):
        source = """-- f(select(2, g()))
local a = "f(select(2, g())) -- multi-value: text"
local b = 'escaped \\' f(select(2, g()))'
local c = [==[ f(select(2, g())) ]=] ]==]
--[==[
f(select(2, g()))
]==]
f(select(2, g()))
"""
        self.assertEqual(Parser(source).check()[0][0], 8)
        self.assertEqual(len(Parser('f("-- multi-value: text", select(2, g()))').check()), 1)

    def test_statement_and_expression_boundaries(self):
        source = """
local a = 0xff + .5 + 1e-3 + 2^3^2
for i = 1, 4 do f(i) end
for k, v in pairs({}) do f(k, v) end
while a > 1 do a = a - 1 end
repeat a = a + 1 until a >= 5
if a then f "string" elseif a == nil then f {} else do f() end end
function object:method(x, ...) return x, ... end
return 1 .. select(2, g())
"""
        self.assertEqual(Parser(source).check(), [])
        self.assertEqual(len(Parser("do return select(2, g()) end\nf(select(2, g()))").check()), 2)

    def test_malformed_input_fails(self):
        for source in ['local s = "unterminated', "--[=[missing end", "f(select(2, g())", "local t = {", "return @"]:
            with self.subTest(source=source), self.assertRaises(LuaSyntaxError):
                Parser(source).check()


if __name__ == "__main__":
    unittest.main()
