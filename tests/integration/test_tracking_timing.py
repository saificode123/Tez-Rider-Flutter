import datetime as dt
import unittest

from tracking_timing import receive_frame, summarize


class TrackingTimingTest(unittest.TestCase):
    def test_blocking_receive_time_is_not_mistaken_for_receipt_time(self):
        ticks = [10.0]
        observed = []

        class Socket:
            def recv(self, timeout):
                self.timeout = timeout
                ticks[0] += .8
                observed.append('received')
                return '{"event":"broadcast"}'

        def wall():
            self.assertEqual(observed, ['received'])
            return dt.datetime(2026, 10, 30, tzinfo=dt.timezone.utc)

        frame, arrived, _ = receive_frame(Socket(), monotonic=lambda: ticks[0], utc_now=wall)
        self.assertEqual(frame['event'], 'broadcast')
        self.assertEqual(arrived, 10.8)

    def test_p95_uses_nearest_rank_and_reports_sample_count(self):
        self.assertEqual(summarize(list(range(1, 21))),
                         {'samples': 20, 'p50': 10.5, 'p95': 19, 'worst': 20})

    def test_empty_capture_does_not_invent_zero_latency(self):
        self.assertEqual(summarize([]), {'samples': 0})

    def test_nonfinite_capture_is_rejected(self):
        with self.assertRaises(ValueError):
            summarize([1, float('nan')])


if __name__ == '__main__':
    unittest.main()
