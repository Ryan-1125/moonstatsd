///|
async test "nested scopes share queue snapshot tags and owner lifetime on real UDP" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let escaped : Ref[@client.Scope?] = Ref(None)
  let mut send_failures = 0
  @async.with_timeout(3000, () => {
    @client.with_client(
      server.addr,
      c => {
        let tags = ["team:api"]
        let scoped = c
          .scope(prefix="http.", tags~)
          .scope(prefix="get.", tags=["route:home"])
        escaped.val = Some(scoped)
        tags[0] = "team:changed"
        ignore(scoped.record("requests", Counter(1.0)))
        ignore(c.record("root", Gauge(2.0)))
        assert_true(
          try {
            ignore(scoped.record("full", Counter(1.0)))
            false
          } catch {
            @client.QueueFull => true
            _ => false
          },
        )
        assert_true(
          try {
            ignore(c.scope(tags=["env:duplicate"]))
            false
          } catch {
            @codec.Invalid(_) => true
            _ => false
          },
        )
        assert_eq(c.flush().submitted, 2L)
        let buffer = FixedArray::make(512, b'\x00')
        let (n, _) = server.recvfrom(buffer)
        assert_eq(
          Bytes::from_array(buffer[:n].to_owned()),
          b"svc.http.get.requests:1|c|#env:test,team:api,route:home\nsvc.root:2|g|#env:test",
        )
      },
      mode=DogStatsD,
      prefix="svc.",
      fixed_tags=["env:test"],
      capacity=2,
      interval_ms=10000,
      on_error=_ => send_failures += 1,
    )
  })
  assert_eq(send_failures, 0)
  if escaped.val is Some(scoped) {
    assert_true(
      try {
        ignore(scoped.record("late", Counter(1.0)))
        false
      } catch {
        @client.Closed => true
        _ => false
      },
    )
  } else {
    fail("scope missing")
  }
}

///|
async test "one shot timer records deterministic milliseconds and snapshots tags" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_timeout(3000, () => {
    @client.with_client(
      server.addr,
      c => {
        let mut now = 100UL
        let tags = ["phase:work"]
        let timer = c
          .scope(prefix="job.")
          .start_timer("latency", tags~, clock=() => now)
        tags[0] = "phase:changed"
        now = 125UL
        assert_eq(timer.stop(), @client.Enqueued)
        assert_true(
          try {
            ignore(timer.stop())
            false
          } catch {
            @client.TimerStopped => true
            _ => false
          },
        )
        assert_eq(c.flush().submitted, 1L)
        let buffer = FixedArray::make(512, b'\x00')
        let (n, _) = server.recvfrom(buffer)
        assert_eq(
          Bytes::from_array(buffer[:n].to_owned()),
          b"job.latency:25|ms|#phase:work",
        )
      },
      mode=DogStatsD,
    )
  })
}

///|
async test "timers validate before start and propagate sampled closed and backwards outcomes" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @client.with_client(
    server.addr,
    c => {
      let mut clock_calls = 0
      assert_true(
        try {
          ignore(
            c.start_timer("bad|name", clock=() => {
              clock_calls += 1
              10UL
            }),
          )
          false
        } catch {
          @codec.Invalid(_) => true
          _ => false
        },
      )
      assert_eq(clock_calls, 0)
      let sampled = c.start_timer("sampled", rate=0.5, clock=() => 10UL)
      assert_eq(sampled.stop(), @client.SampledOut)
      let mut now = 20UL
      let backwards = c.start_timer("backwards", clock=() => now)
      now = 10UL
      assert_true(
        try {
          ignore(backwards.stop())
          false
        } catch {
          @client.InvalidConfig(_) => true
          _ => false
        },
      )
      let closed = c.start_timer("closed")
      ignore(c.close())
      assert_true(
        try {
          ignore(closed.stop())
          false
        } catch {
          @client.Closed => true
          _ => false
        },
      )
      assert_eq(c.stats().enqueued, 0L)
      assert_eq(c.stats().sampled_out, 1L)
    },
    random=() => 0.75,
  )
}
