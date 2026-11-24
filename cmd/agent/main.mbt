///|
async fn main {
  let address = @socket.Addr::parse(
    @env.get_env_var("MOONSTATSD_ADDR").unwrap_or("127.0.0.1:19128"),
  )
  @client.with_client(
    address,
    c => {
      ignore(c.record("count", Counter(2.0), rate=0.5))
      ignore(c.record("queue", Gauge(7.0)))
      ignore(c.record("timer", Timer(250.0)))
      ignore(c.record("payload", Histogram(42.0)))
      ignore(c.record("unique", Set("alice")))
      ignore(c.record("unique", Set("alice")))
      ignore(c.record("unique", Set("bob")))
      ignore(
        c.event(
          "MoonStatsD expanded",
          "deployed|ok\nline2",
          aggregation_key="release",
          alert=Success,
          hostname="moonstatsd-node",
        ),
      )
      ignore(
        c.service_check(
          "health",
          Critical,
          message="failure\nm:ready",
          hostname="moonstatsd-node",
        ),
      )
      ignore(c.record_values("packed", [Timer(10.0), Timer(20.0)]))
      let window = @codec.AggregateBuffer::new()
      window.record("agg.count", Counter(1.0))
      window.record("agg.count", Counter(2.0))
      window.record("agg.gauge", Gauge(1.0))
      window.record("agg.gauge", Gauge(4.0))
      window.record("agg.set", Set("alice"))
      window.record("agg.set", Set("alice"))
      window.record("agg.hist", Histogram(2.0))
      window.record("agg.hist", Histogram(4.0))
      assert_eq(c.submit_aggregate(window), 4)
      let report = c.close()
      if report.submitted != 14 ||
        report.send_errors != 0 ||
        report.dropped != 0 {
        fail("Agent workload did not submit all metrics locally")
      }
      println(
        "Agent workload submitted=\{report.submitted}; no collector acknowledgement implied",
      )
    },
    mode=DogStatsD,
    prefix="moonagent.",
    fixed_tags=["env:test", "service:demo", "route:home"],
    random=() => 0.1,
  )
}
