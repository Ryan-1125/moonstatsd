///|
test "events UTF8 escaping metadata and check ordering" {
  assert_eq(
    @moonstatsd.encode_event(
      "发布",
      "a\nb",
      timestamp=10L,
      hostname="node",
      aggregation_key="deploy",
      source_type="ci",
      priority=Low,
      alert=Success,
      tags=["env:test"],
    ).bytes(),
    b"_e{6,4}:\xe5\x8f\x91\xe5\xb8\x83|a\\nb|d:10|h:node|k:deploy|p:low|s:ci|t:success|#env:test",
  )
  assert_eq(
    @moonstatsd.encode_check(
      "health",
      Critical,
      timestamp=10L,
      hostname="node",
      tags=["env:test"],
      message="a\nm:b",
    ).bytes(),
    b"_sc|health|2|d:10|h:node|#env:test|m:a\\nm\\:b",
  )
}

///|
test "packing shares type tags and rate and rejects set mixed and oversize" {
  assert_eq(
    @moonstatsd.encode_values(
      "latency",
      [Timer(1.0), Timer(2.0)],
      tags=["a:b"],
      rate=0.5,
    ).bytes(),
    b"latency:1:2|ms|@0.5|#a:b",
  )
  let bad : Array[() -> @moonstatsd.Message raise @moonstatsd.EncodeError] = [
    () => @moonstatsd.encode_values("x", []),
    () => @moonstatsd.encode_values("x", [Set("a")]),
    () => @moonstatsd.encode_values("x", [Counter(1.0), Gauge(2.0)]),
    () => {
      @moonstatsd.encode_values("x", [Counter(1.0), Counter(2.0)], max_bytes=5)
    },
    () => @moonstatsd.encode_event("x", "a\r#inject"),
    () => @moonstatsd.encode_check("x", Ok, message="a\rb"),
    () => @moonstatsd.encode_event("x", "y", timestamp=-1L),
  ]
  for f in bad {
    assert_true(
      try {
        ignore(f())
        false
      } catch {
        _ => true
      },
    )
  }
}

///|
test "aggregate semantics bounded storage snapshots and reset" {
  let window = @moonstatsd.AggregateBuffer::new(capacity=5)
  window.record("c", Counter(1.0))
  window.record("c", Counter(2.0))
  window.record("g", Gauge(1.0))
  window.record("g", Gauge(3.0))
  window.record("s", Set("a"))
  window.record("s", Set("a"))
  window.record("h", Histogram(2.0))
  window.record("h", Histogram(3.0))
  assert_eq(window.length(), 5)
  assert_true(
    try {
      window.record("extra", Counter(1.0))
      false
    } catch {
      _ => true
    },
  )
  let messages = window.messages()
  assert_eq(messages[0].bytes(), b"c:3|c")
  assert_eq(messages[1].bytes(), b"g:3|g")
  assert_eq(messages[2].bytes(), b"s:a|s")
  assert_eq(messages[3].bytes(), b"h:2:3|h")
  assert_eq(messages.length(), 4)
  window.clear()
  assert_eq(window.length(), 0)
}

///|
test "event length framing safely contains pipes and exact UTF8 byte limits" {
  let wire = @moonstatsd.encode_event("a|b", "x|y\nz").bytes()
  assert_eq(wire, b"_e{3,6}:a|b|x|y\\nz|p:normal|t:info")
  assert_eq(
    @moonstatsd.encode_event("a|b", "x|y\nz", max_bytes=wire.length()).bytes(),
    wire,
  )
  assert_true(
    try {
      ignore(
        @moonstatsd.encode_event("a|b", "x|y\nz", max_bytes=wire.length() - 1),
      )
      false
    } catch {
      @moonstatsd.TooLarge(_, _) => true
      _ => false
    },
  )
  assert_eq(@moonstatsd.encode_check("x", Ok).bytes(), b"_sc|x|0")
  assert_eq(@moonstatsd.encode_check("x", Warning).bytes(), b"_sc|x|1")
  assert_eq(@moonstatsd.encode_check("x", Critical).bytes(), b"_sc|x|2")
  assert_eq(@moonstatsd.encode_check("x", Unknown).bytes(), b"_sc|x|3")
}

///|
test "aggregate mixed observation types splitting overflow and tag snapshot" {
  let buffer = @moonstatsd.AggregateBuffer::new(max_bytes=8)
  buffer.record("x", Timer(1.0))
  buffer.record("x", Timer(2.0))
  buffer.record("x", Timer(3.0))
  buffer.record("x", Histogram(4.0))
  let packed = buffer.messages()
  assert_eq(packed[0].bytes(), b"x:1:2|ms")
  assert_eq(packed[1].bytes(), b"x:3|ms")
  assert_eq(packed[2].bytes(), b"x:4|h")
  let other = @moonstatsd.AggregateBuffer::new()
  let tags = ["env:before"]
  other.record("x", Counter(1.0e308), tags~)
  assert_true(
    try {
      other.record("x", Counter(1.0e308), tags~)
      false
    } catch {
      @moonstatsd.Invalid(_) => true
      _ => false
    },
  )
  tags[0] = "env:after"
  assert_eq(other.length(), 1)
  assert_eq(other.messages()[0].bytes(), b"x:1e+308|c|#env:before")
}
