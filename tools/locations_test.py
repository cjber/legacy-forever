import unittest

from locations import same_name


class SameName(unittest.TestCase):
    def test_respelling_is_the_same_name(self):
        self.assertTrue(same_name("Zul'farrak", "Zul'Farrak"))
        self.assertTrue(same_name("Diremaul: East", "Dire Maul - East"))

    def test_another_name_is_not(self):
        self.assertFalse(same_name("Scarlet Monastery: Armory", "Scarlet Monastery: Cathedral"))
        self.assertFalse(same_name("Stratholme: Live", "Stratholme: Dead"))


if __name__ == "__main__":
    unittest.main()
