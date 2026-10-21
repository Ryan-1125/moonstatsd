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
      let report = c.close()
      if report.submitted != 7 || report.send_errors != 0 || report.dropped != 0 {
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
