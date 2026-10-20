// Test output adapter only. The upstream StatsD v0.9.0 process owns UDP parsing,
// sampling, gauge arithmetic, timer storage and set uniqueness.
exports.init = function (_startup, _config, events) {
  events.on('flush', (_timestamp, metrics) => {
    const sets = Object.fromEntries(Object.entries(metrics.sets).map(([k,v]) => [k,v.values()]));
    console.log('MOONSTATSD_JSON=' + JSON.stringify({counters:metrics.counters, gauges:metrics.gauges, timers:metrics.timers, sets}));
  });
  return true;
};
