import unittest

from dictionary_sources import british_ipa, parse_sections


class SourceCleanupTests(unittest.TestCase):
    def test_literal_and_actual_line_breaks(self):
        sections = parse_sections('n. first\\r\\n\\r\\nsecond\r\n  continued\\n\\r')
        definitions = [sense['definition'] for section in sections for sense in section['senses']]
        self.assertEqual(definitions, ['first', 'second continued'])

    def test_empty_part_of_speech_is_not_a_sense(self):
        self.assertEqual(parse_sections('n. \\r'), [])

    def test_corrupt_ipa_is_not_guessed(self):
        self.assertIsNone(british_ipa("'p\\\\\\\\:sәnәlaiz"))
        self.assertEqual(british_ipa('ˈpɜːsənəlaɪz'), '/ˈpɜːsənəlaɪz/')
        self.assertEqual(british_ipa("'pә:sәnәlaiz"), '/ˈpəːsənəlaɪz/')


if __name__ == '__main__':
    unittest.main()
