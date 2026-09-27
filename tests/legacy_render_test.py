"""Data/Legacy.lua string literals decode back to the value legacy_render wrote, with Lua 5.1's escapes."""

import unittest

from tools.legacy_render import lua_string, lua_unquote


class LuaStringTests(unittest.TestCase):
    def test_round_trip(self):
        for value in ["plain", 'say "hi"', "back\\slash", "tab\there", "line\nbreak\r", "\x00\x1f", "Zul'Farrak ü"]:
            with self.subTest(value=value):
                self.assertEqual(lua_unquote(lua_string(value)), value)

    def test_lua_escapes(self):
        self.assertEqual(lua_unquote(r'"\0659"'), "A9")  # at most three digits
        self.assertEqual(lua_unquote(r'"\9x"'), "\tx")
        self.assertEqual(lua_unquote(r'"\195\188"'), "ü")  # \ddd is a byte
        self.assertEqual(lua_unquote(r'"\a\b\f\n\r\t\v\'"'), "\a\b\f\n\r\t\v'")
        with self.assertRaises(ValueError):
            lua_unquote(r'"\256"')


if __name__ == "__main__":
    unittest.main()
