import QtQuick
import QtTest
import "ChartMath.js" as ChartMath

Item {
    width: 640
    height: 320
    PowerHistoryChart { id: chart; anchors.fill: parent }
    TestCase {
        name: "PowerChart"
        when: windowShown
        function point(t, power, gap) {
            return { timestamp: t, battery_power_w: power, percentage: 60 + t / 100,
                voltage_v: 12 + t / 1000, gap_before: !!gap };
        }
        function test_domains_and_missing_values() {
            compare(ChartMath.domain([], "charge"), [0, 100]);
            const zero = ChartMath.domain([point(0, 0)], "power");
            verify(zero[1] > zero[0]);
            const signed = ChartMath.domain([point(0, -17), point(2, 8)], "power");
            verify(signed[0] < -17 && signed[1] > 8);
            const noValue = point(0, null);
            compare(ChartMath.segments([noValue], "power").length, 0);
            const voltage = ChartMath.domain([point(0, 1)], "voltage");
            verify(voltage[1] > voltage[0]);
        }
        function test_gaps_and_extrema_do_not_get_smoothed_away() {
            const parts = ChartMath.segments([point(0, 1), point(2, 9), point(4, 1), point(20, 3, true)], "power");
            compare(parts.length, 2);
            compare(parts[0].length, 3);
            compare(ChartMath.nearest([point(0, 1), point(2, 9), point(300, 3, true)], 150, "power"), null);
            const missing = point(4, 3);
            missing.gaps_before = ["battery_power_w"];
            compare(ChartMath.segments([point(0, 1), point(2, 2), missing], "power").length, 2);
            compare(ChartMath.segments([point(0, 1), point(2, 2), missing], "voltage").length, 1);
            const slopes = ChartMath.tangents([{ x: 0, y: 1 }, { x: 1, y: 9 }, { x: 2, y: 1 }]);
            compare(slopes[1], 0);
            compare(ChartMath.nearest([point(0, 1), point(2, 9)], 1.8, "power").timestamp, 2);
        }
        function test_period_metric_transitions_and_paint() {
            chart.metric = "power";
            chart.history = { points: [point(0, -17), point(2, -16), point(4, -18)], window_start: -1196, window_end: 4 };
            wait(80);
            chart.history = { points: [point(0, -17), point(2, -16), point(4, -18)], window_start: -3596, window_end: 4 };
            verify(chart.blend < 1);
            tryCompare(chart, "blend", 1, 1000);
            compare(chart.frame.start, -3596);
            chart.metric = "charge";
            tryCompare(chart, "blend", 1, 1000);
            compare(chart.frame.low, 0);
            compare(chart.frame.high, 100);
            const image = grabImage(chart);
            verify(image.width > 0 && image.height > 0);
            chart.visible = false;
            compare(chart.blend, 1);
            chart.visible = true;
        }
    }
}
