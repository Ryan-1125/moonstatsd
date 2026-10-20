///|
async test "real UDP packet limits flush and repeat close" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_timeout(3000, () => {
    @client.with_client(
      server.addr,
      c => {
        ignore(c.record("a", Counter(1.0)))
        ignore(c.record("b", Counter(2.0)))
        ignore(c.record("c", Counter(3.0)))
        let report = c.flush()
        assert_eq(report.submitted, 3L)
        assert_eq(report.pending, 0L)
        let buf = FixedArray::make(128, b'\x00')
        let (n, _) = server.recvfrom(buf)
        assert_eq(Bytes::from_array(buf[:n].to_owned()), b"a:1|c\nb:2|c")
        let (n, _) = server.recvfrom(buf)
        assert_eq(Bytes::from_array(buf[:n].to_owned()), b"c:3|c")
        let closed = c.close()
        assert_true(closed.closed)
        assert_eq(c.close().submitted, 3L)
        assert_eq(c.flush().submitted, 3L)
        assert_true(
          try {
            ignore(c.record("x", Counter(1.0)))
            false
          } catch {
            @client.Closed => true
            _ => false
          },
        )
      },
      max_bytes=11,
      interval_ms=10000,
    )
  })
}

///|
async test "bounded queue sampling and idle timer on real UDP" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_timeout(3000, () => {
    @client.with_client(
      server.addr,
      c => {
        assert_eq(c.record("skip", Counter(1.0), rate=0.5), @client.SampledOut)
        ignore(c.record("a", Counter(1.0)))
        ignore(c.record("b", Counter(1.0)))
        assert_true(
          try {
            ignore(c.record("full", Counter(1.0)))
            false
          } catch {
            @client.QueueFull => true
            _ => false
          },
        )
        ignore(c.flush())
        let buf = FixedArray::make(128, b'\x00')
        let (n, _) = server.recvfrom(buf)
        assert_eq(n, 11)
        ignore(c.record("idle", Gauge(9.0)))
        let (n, _) = server.recvfrom(buf)
        assert_eq(Bytes::from_array(buf[:n].to_owned()), b"idle:9|g")
        let stats = c.close()
        assert_eq(stats.sampled_out, 1L)
        assert_eq(stats.queue_full, 1L)
        assert_eq(stats.submitted, 3L)
        assert_eq(stats.dropped, 0L)
      },
      capacity=2,
      interval_ms=20,
      random=() => 0.5,
    )
  })
}

///|
async test "cooperative producers flush and close compete" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @async.with_timeout(3000, () => {
    @client.with_client(server.addr, c => {
      @async.with_task_group(g => {
        for i in 0..<4 {
          g.spawn_bg(() => ignore(c.record("producer\{i}", Counter(1.0))))
        }
      })
      @async.with_task_group(g => {
        g.spawn_bg(() => ignore(c.flush()))
        g.spawn_bg(() => ignore(c.close()))
        g.spawn_bg(() => ignore(c.close()))
      })
      assert_eq(c.stats().enqueued, 4L)
      assert_eq(c.stats().submitted, 4L)
      assert_true(c.stats().closed)
    })
  })
}

///|
async test "escaped client closes on callback failure" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let mut saved : @client.Client? = None
  @client.with_client(
    server.addr,
    c => {
      saved = Some(c)
      ignore(c.record("pending", Counter(1.0)))
      fail("callback failure")
    },
    interval_ms=10000,
  ) catch {
    _ => ()
  }
  let c = saved.unwrap()
  assert_true(c.stats().closed)
  assert_eq(c.stats().pending, 0L)
  assert_eq(c.stats().dropped, 1L)
}

///|
async test "scope cancellation drops pending and closes escaped handle" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let mut saved : @client.Client? = None
  let result = @async.with_timeout_opt(30, () => {
    @client.with_client(
      server.addr,
      c => {
        saved = Some(c)
        ignore(c.record("pending", Counter(1.0)))
        @async.sleep(10000)
      },
      interval_ms=10000,
    )
  })
  assert_true(result is None)
  let c = saved.unwrap()
  assert_true(c.stats().closed)
  assert_eq(c.stats().dropped, 1L)
}

///|
async test "cancelled flush waiter does not cancel sender" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @client.with_client(
    server.addr,
    c => {
      // Fill many one-metric packets; pause in the sender guarantees cooperative yield.
      for _ in 0..<100 {
        ignore(c.record("a", Counter(1.0)))
      }
      @async.with_task_group(g => {
        let waiter = g.spawn(() => ignore(c.flush()))
        @async.pause()
        waiter.cancel()
        waiter.wait() catch {
          _ => ()
        }
      })
      let report = c.close()
      assert_eq(report.submitted, 100L)
      assert_eq(report.dropped, 0L)
    },
    capacity=128,
    max_bytes=5,
    interval_ms=10000,
  )
}

///|
async test "cancelled close cancels sender and drops backlog" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  @client.with_client(
    server.addr,
    c => {
      for _ in 0..<100 {
        ignore(c.record("a", Counter(1.0)))
      }
      @async.with_task_group(g => {
        let closer = g.spawn(() => ignore(c.close()))
        @async.pause()
        closer.cancel()
        closer.wait() catch {
          _ => ()
        }
      })
      let report = c.close()
      assert_true(report.closed)
      assert_eq(report.pending, 0L)
      assert_eq(report.submitted + report.dropped, 100L)
      assert_true(report.dropped > 0)
    },
    capacity=128,
    max_bytes=5,
    interval_ms=10000,
  )
}
