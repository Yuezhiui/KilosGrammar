"""Offline camera-free preview ordering and slow-YOLO freshness regressions.

The timestamps are from one synthetic Python monotonic clock. No webcam,
database, captured student images or external service is ever used here.
"""

import unittest
from unittest.mock import patch

import pose_worker


class CapturedPackets:
    def __init__(self):
        self.packets = []

    def sendto(self, data, _destination):
        self.packets.append(data)


def unpack(packet):
    assert packet[0] == 2
    metadata, pixels = packet[1:].split(b";", 1)
    timestamp, inferred, people, age, foreground = metadata.decode("ascii").split(",")
    assert 0 <= int(age) <= 650
    assert int(foreground) >= -1
    return float(timestamp), int(inferred), int(people), pixels


class PreviewSourceFreshnessTests(unittest.TestCase):
    def setUp(self):
        self.now = [100.0]
        self.clock = patch.object(pose_worker.time, "monotonic", lambda: self.now[0])
        self.clock.start()
        self.addCleanup(self.clock.stop)
        self.sock = CapturedPackets()
        self.publisher = pose_worker.PreviewPublisher(self.sock, ("127.0.0.1", 43123))

    def publish(self, source, inferred=True, people=1, payload=b"camera"):
        return self.publisher.publish(payload, source, inferred, people)

    def test_two_five_ten_and_twenty_fps_never_interleave_blank_raw_frames(self):
        for fps in (2, 5, 10, 20):
            with self.subTest(inference_fps=fps):
                self.now[0] = 100.0
                self.sock.packets.clear()
                self.publisher = pose_worker.PreviewPublisher(
                    self.sock, ("127.0.0.1", 43123))
                period = 1.0 / fps
                for frame in range(1, fps * 4 + 1):
                    self.now[0] = 100.0 + frame * period
                    # Real inference is complete before the next camera frame.
                    self.assertTrue(self.publish(self.now[0], people=1))
                    self.assertFalse(self.publisher.raw_fallback_due(self.now[0]),
                                     "A live YOLO preview must keep its green bones")
                    self.now[0] += period * 0.7
                    self.assertFalse(self.publisher.raw_fallback_due(self.now[0]))
                self.assertEqual(len(self.sock.packets), fps * 4)
                self.assertTrue(all(unpack(p)[1:3] == (1, 1) for p in self.sock.packets))

    def test_occlusion_or_stall_can_show_only_new_fresh_raw_pixels(self):
        self.assertTrue(self.publish(100.0))
        self.now[0] = 101.14
        self.assertFalse(self.publisher.raw_fallback_due(self.now[0]))
        self.now[0] = 101.16
        self.assertTrue(self.publisher.raw_fallback_due(self.now[0]))
        self.assertTrue(self.publish(101.16, inferred=False, people=-1, payload=b"raw-no-bones"))
        self.assertEqual(unpack(self.sock.packets[-1])[1:], (0, -1, b"raw-no-bones"))
        # An encoder finishing an older inferred image after fallback cannot
        # put a remembered skeleton on screen, regardless of JPEG order.
        self.assertFalse(self.publish(101.0, inferred=True, people=1, payload=b"old-green"))
        self.assertEqual(len(self.sock.packets), 2)
        self.now[0] = 101.3
        self.assertFalse(self.publisher.raw_fallback_due(self.now[0]))
        self.now[0] = 101.32
        self.assertTrue(self.publisher.raw_fallback_due(self.now[0]))
        self.assertTrue(self.publish(101.32, inferred=False, payload=b"still-raw"))
        self.now[0] = 101.52
        self.assertTrue(self.publish(101.52, inferred=True, people=1,
                                     payload=b"new-real-green"))
        self.assertFalse(self.publisher.raw_fallback_due(self.now[0]))
        self.assertEqual(unpack(self.sock.packets[-1])[3], b"new-real-green")

    def test_expired_camera_samples_are_never_republished_as_live_bones(self):
        self.now[0] = 100.65
        self.assertFalse(self.publish(99.999, inferred=True, people=1))
        self.assertFalse(self.publish(99.999, inferred=False, people=-1))
        self.assertFalse(self.publish(100.7, inferred=True, people=1),
                         "A future timestamp is also invalid")
        self.assertTrue(self.publish(100.1, inferred=True, people=1))
        self.now[0] = 101.0
        self.assertFalse(self.publish(100.1, inferred=True, people=1))
        self.assertEqual(len(self.sock.packets), 1)

    def test_crowd_and_empty_camera_frames_are_not_claimed_as_solo(self):
        self.now[0] = 100.1
        self.assertTrue(self.publish(100.1, inferred=True, people=1))
        self.now[0] = 100.3
        self.assertTrue(self.publish(100.3, inferred=True, people=2))
        self.now[0] = 100.5
        self.assertTrue(self.publish(100.5, inferred=True, people=0))
        self.assertEqual([unpack(p)[2] for p in self.sock.packets], [1, 2, 0])
        self.assertFalse(self.publish(100.3, inferred=True, people=1,
                                      payload=b"old-solo-after-crowd"))
        self.now[0] = 100.7
        self.assertTrue(self.publish(100.7, inferred=True, people=1,
                                     payload=b"fresh-solo-after-reacquisition"))
        self.assertEqual(unpack(self.sock.packets[-1])[3],
                         b"fresh-solo-after-reacquisition")


if __name__ == "__main__":
    unittest.main()
