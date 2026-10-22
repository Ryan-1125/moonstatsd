///|
/// Self-contained diagnostic example using a real local UDP receiver.
async fn main {
  let receiver = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer receiver.close()
  @async.with_timeout(3000, () => {
    @client.with_client(
      receiver.addr,
      client => {
        let jobs = client.scope(prefix="jobs.", tags=["team:worker"])
        let timer = jobs.start_timer("duration")
        @async.sleep(10)
        ignore(timer.stop())
        ignore(jobs.record("completed", Counter(1.0)))
        // Admission failures are synchronous; asynchronous sends use on_error.
        ignore(jobs.record("overflow", Counter(1.0))) catch {
          @client.QueueFull => println("queue full: newest metric rejected")
          err => raise err
        }
        let report = client.flush()
        let buffer = FixedArray::make(512, b'\x00')
        let (n, _) = receiver.recvfrom(buffer)
        println("real UDP received bytes=\{n}")
        println(
          "submitted=\{report.submitted}, queue_full=\{report.queue_full}, dropped=\{report.dropped}",
        )
      },
      mode=DogStatsD,
      capacity=2,
      interval_ms=10000,
      on_error=event => {
        println(
          "local send failed: \{event.message}; metrics=\{event.metrics}, pending=\{event.stats.pending}",
        )
      },
    )
  })
}
