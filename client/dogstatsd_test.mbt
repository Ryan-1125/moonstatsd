///|
async test "events checks packed values and aggregate window on real UDP" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_timeout(3000, () => {
    @client.with_client(
      server.addr,
      c => {
        ignore(c.event("deploy", "ok"))
        ignore(c.service_check("health", Ok, message="ready"))
        ignore(c.record_values("latency", [Timer(1.0), Timer(2.0)]))
        let window = @codec.AggregateBuffer::new()
        window.record("count", Counter(1.0))
        window.record("count", Counter(2.0))
        assert_eq(
          c.scope(prefix="jobs.", tags=["team:w"]).submit_aggregate(window),
          1,
        )
        assert_eq(window.length(), 0)
        assert_eq(c.flush().submitted, 4L)
        let buffer = FixedArray::make(512, b'\x00')
        let (n, _) = server.recvfrom(buffer)
        assert_eq(
          Bytes::from_array(buffer[:n].to_owned()),
          b"_e{6,2}:deploy|ok|p:normal|t:info\n_sc|svc.health|0|m:ready\nsvc.latency:1:2|ms\nsvc.jobs.count:3|c|#team:w",
        )
      },
      mode=DogStatsD,
      prefix="svc.",
      interval_ms=10000,
    )
  })
}

///|
async test "aggregate backpressure is atomic and retryable" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @client.with_client(
    server.addr,
    c => {
      let window = @codec.AggregateBuffer::new()
      ignore(c.record("existing", Counter(1.0)))
      window.record("a", Counter(1.0))
      window.record("b", Counter(2.0))
      assert_true(
        try {
          ignore(c.submit_aggregate(window))
          false
        } catch {
          @client.QueueFull => true
          _ => false
        },
      )
      assert_eq(window.length(), 2)
      assert_eq(c.stats().enqueued, 1L)
      ignore(c.flush())
      assert_eq(c.submit_aggregate(window), 2)
      assert_eq(window.length(), 0)
      assert_eq(c.flush().submitted, 3L)
    },
    mode=DogStatsD,
    capacity=2,
  )
}
