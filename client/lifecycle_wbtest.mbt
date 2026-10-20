///|
// Deliberately unstarted owner for deterministic timeout tests. Not a transport mock.
fn idle_client() -> Client {
  {
    mode: StatsD,
    prefix: "",
    tags: [],
    max_bytes: 512,
    capacity: 2,
    interval_ms: 10000,
    timeout_ms: 100,
    draw: () => 0.25,
    queue: @deque.Deque([]),
    wake: @cond.Cond(),
    changed: @cond.Cond(),
    worker: None,
    requested: false,
    state: 0,
    accepted: 0,
    done: 0,
    sampled_out: 0,
    queue_full: 0,
    submitted: 0,
    send_errors: 0,
    dropped: 0,
  }
}

///|
async test "real closed socket error is accounted without retries" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let socket = @socket.UdpClient(server.addr)
  socket.close()
  let c = idle_client()
  ignore(c.record("x", Counter(1.0)))
  @async.with_task_group(g => {
    let sender = g.spawn(() => c.send_loop(socket), no_wait=true)
    c.worker = Some(sender)
    defer sender.cancel()
    let report = c.flush()
    assert_eq(report.submitted, 0L)
    assert_eq(report.send_errors, 1L)
    assert_eq(report.dropped, 1L)
    ignore(c.close())
  })
}

///|
async test "flush timeout preserves pending; close timeout rejects new admission" {
  let c = idle_client()
  ignore(c.record("x", Counter(1.0)))
  let flushed = @async.with_timeout_opt(10, () => c.flush(timeout_ms=100))
  assert_true(flushed is None)
  assert_eq(c.stats().pending, 1L)
  assert_eq(c.state, 0)
  let timed_out = try {
    ignore(c.close(timeout_ms=5))
    false
  } catch {
    @async.TimeoutError => true
    _ => false
  }
  assert_true(timed_out)
  assert_eq(c.state, 1)
  assert_true(
    try {
      ignore(c.record("x", Counter(1.0)))
      false
    } catch {
      Closed => true
      _ => false
    },
  )
}
