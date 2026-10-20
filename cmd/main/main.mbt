///|
async fn main {
  let addr = @socket.Addr::parse(
    @env.get_env_var("MOONSTATSD_ADDR").unwrap_or("127.0.0.1:19125"),
  )
  @client.with_client(
    addr,
    c => {
      // Request completion: low-cardinality route and status.
      ignore(
        c.record("requests", Counter(2.0), tags=["route:home", "status:200"]),
      )
      ignore(c.record("latency", Timer(250.0), tags=["route:home"]))
      // Background job completion, then explicit barrier before shutdown.
      ignore(c.record("jobs", Counter(1.0), tags=["result:success"]))
      ignore(c.record("job_time", Timer(1500.0)))
      ignore(c.flush())
      // Worker snapshots; relative gauge updates use StatsD mode (cmd/statsd).
      ignore(c.record("queue", Gauge(10.0)))
      ignore(c.record("queue", Gauge(7.0)))
      ignore(c.record("active", Gauge(2.0)))
      ignore(c.record("payload", Histogram(42.0)))
      ignore(c.record("distribution", Distribution(5.0)))
      ignore(c.close())
      let report = c.stats()
      println(
        "submitted=\{report.submitted} send_errors=\{report.send_errors} dropped=\{report.dropped} closed=\{report.closed}",
      )
    },
    mode=DogStatsD,
    prefix="moon.",
    fixed_tags=["service:demo", "env:test"],
  )
}
