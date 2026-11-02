"""Synthetic no-camera, no-DB checks for two-player classroom association."""
import unittest

try:
    from .two_player_lock import TwoPlayerLock
except ImportError:
    from two_player_lock import TwoPlayerLock


def person(x, height=.55, index=0):
    points = [[x, .5, .95] for _ in range(17)]
    return {"x": x, "height": height, "keypoints": points,
            "detection_index": index}


class TwoPlayerSessionTests(unittest.TestCase):
    def hold(self, tracker, people, start=0.0):
        output = None
        for index in range(12):
            output = tracker.update(people, start + index * .1)
        return output

    def test_two_slots_lock_separately_and_ignore_small_spectator(self):
        lock = TwoPlayerLock()
        output = self.hold(lock, [person(.25, .50, 0), person(.73, .54, 1),
                                  person(.96, .12, 2)])
        self.assertEqual([p["active"] for p in output], [True, True])
        self.assertEqual([round(p["x"], 2) for p in output], [.25, .73])
        output = lock.update([person(.27, .50, 0), person(.68, .54, 1)], 1.2)
        self.assertEqual([p["active"] for p in output], [True, True])

    def test_one_player_missing_never_swaps_slots(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25, index=0), person(.73, index=1)])
        output = lock.update([person(.72, index=1)], 1.2)
        self.assertFalse(output[0]["active"])
        self.assertTrue(output[1]["active"])
        self.assertEqual(output[1]["index"], 1)

    def test_isolated_hand_is_not_enrolled(self):
        lock = TwoPlayerLock()
        hand = person(.26)
        hand["keypoints"] = []
        output = self.hold(lock, [hand, person(.75)])
        self.assertEqual([p["active"] for p in output], [False, False])

    def test_crossing_without_clear_separation_never_automatically_swaps(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25, index=0), person(.75, index=1)])
        output = lock.update([person(.48, index=0), person(.50, index=1)], 1.2)
        self.assertFalse(any(p["active"] for p in output))

    def test_no_person_does_not_emit_ghost_skeleton(self):
        lock = TwoPlayerLock()
        self.hold(lock, [person(.25), person(.75)])
        output = lock.update([], 1.2)
        self.assertEqual([p["active"] for p in output], [False, False])
        self.assertEqual([p["index"] for p in output], [-1, -1])


if __name__ == "__main__":
    unittest.main()
