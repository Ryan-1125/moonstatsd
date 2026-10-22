///|
// Deliberately unstarted owner for deterministic timeout tests. Not a transport mock.
fn idle_client(on_error? : (SendFailure) -> Unit) -> Client {
  {
    mode: StatsD,
    prefix: "",
    tags: [],
    max_bytes: 512,
    capacity: 2,
    interval_ms: 10000,
    timeout_ms: 100,
    draw: () => 0.25,
    on_error,
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
    last_send_error: None,
    dropped: 0,
  }
}

///|
test "full queue consumes a timer stop attempt without duplicate admission" {
  let c = idle_client()
  let timer = c.start_timer("duration", clock=() => 10UL)
  ignore(c.record("x", Counter(1.0)))
  ignore(c.record("y", Counter(1.0)))
  assert_true(
    try {
      ignore(timer.stop())
      false
    } catch {
      QueueFull => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(timer.stop())
      false
    } catch {
      TimerStopped => true
      _ => false
    },
  )
  assert_eq(c.stats().enqueued, 2L)
  assert_eq(c.stats().queue_full, 1L)
}

///|
async test "send failure hook observes committed accounting and can admit another metric" {
  let server = @socket.UdpServer(@socket.Addr::parse("127.0.0.1:0"))
  defer server.close()
  let socket = @socket.UdpClient(server.addr)
  socket.close()
  let events : Array[SendFailure] = []
  let handle : Ref[Client?] = Ref(None)
  let c = idle_client(on_error=event => {
    events.push(event)
    if events.length() == 1 && handle.val is Some(owner) {
      ignore(owner.record("next", Counter(1.0)) catch { _ => SampledOut })
    }
  })
  handle.val = Some(c)
  ignore(c.record("x", Counter(1.0)))
  @async.with_task_group(g => {
    let sender = g.spawn(() => c.send_loop(socket), no_wait=true)
    c.worker = Some(sender)
    defer sender.cancel()
    ignore(c.flush())
    ignore(c.close())
  })
  assert_eq(events.length(), 2)
  assert_eq(events[0].metrics, 1L)
  assert_eq(events[0].bytes, 5)
  assert_eq(events[0].stats.pending, 0L)
  assert_eq(events[0].stats.send_errors, 1L)
  assert_eq(events[0].stats.dropped, 1L)
  assert_true(!events[0].message.is_empty())
  assert_eq(events[1].stats.send_errors, 2L)
  assert_eq(c.stats().dropped, 2L)
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
    assert_true(report.last_send_error is Some(text) && !text.is_empty())
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
