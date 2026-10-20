///|
test "fixed vectors and extensions" {
  assert_eq(
    @moonstatsd.encode("requests", Counter(2.0)).bytes(),
    b"requests:2|c",
  )
  assert_eq(@moonstatsd.encode("queue", Gauge(3.0)).bytes(), b"queue:3|g")
  assert_eq(@moonstatsd.encode("queue", GaugeDelta(2.0)).bytes(), b"queue:+2|g")
  assert_eq(
    @moonstatsd.encode("queue", GaugeDelta(-2.0)).bytes(),
    b"queue:-2|g",
  )
  assert_eq(
    @moonstatsd.encode("latency", Timer(12.5), rate=0.5).bytes(),
    b"latency:12.5|ms|@0.5",
  )
  assert_eq(@moonstatsd.encode("unique", Set("abc")).bytes(), b"unique:abc|s")
  assert_eq(
    @moonstatsd.encode(
      "size",
      Histogram(4.0),
      mode=DogStatsD,
      prefix="svc.",
      fixed_tags=["env:test"],
      tags=["route:home"],
    ).bytes(),
    b"svc.size:4|h|#env:test,route:home",
  )
  assert_eq(
    @moonstatsd.encode("size", Distribution(4.0), mode=DogStatsD).bytes(),
    b"size:4|d",
  )
}

///|
test "rejections are explicit" {
  let bad : Array[() -> @moonstatsd.Message raise @moonstatsd.EncodeError] = [
    fn() raise @moonstatsd.EncodeError { @moonstatsd.encode("q", Gauge(-1.0)) },
    fn() raise @moonstatsd.EncodeError {
      @moonstatsd.encode("q\nx:1|c", Counter(1.0))
    },
    fn() raise @moonstatsd.EncodeError { @moonstatsd.encode("x", Set("a|c")) },
    fn() raise @moonstatsd.EncodeError {
      @moonstatsd.encode("x", Counter(1.0), tags=["a:b"])
    },
    fn() raise @moonstatsd.EncodeError {
      @moonstatsd.encode("x", Histogram(1.0))
    },
    fn() raise @moonstatsd.EncodeError {
      @moonstatsd.encode("x", Counter(1.0), rate=0.0)
    },
    fn() raise @moonstatsd.EncodeError {
      @moonstatsd.encode("x", Counter(1.0), rate=1.1)
    },
    fn() raise @moonstatsd.EncodeError {
      @moonstatsd.encode("x", Gauge(1.0), rate=0.5)
    },
    fn() raise @moonstatsd.EncodeError {
      @moonstatsd.encode("x", Counter(1.0), mode=DogStatsD, tags=["a:b,c:d"])
    },
    fn() raise @moonstatsd.EncodeError {
      @moonstatsd.encode(
        "x",
        Counter(1.0),
        mode=DogStatsD,
        fixed_tags=["a:b"],
        tags=["a:c"],
      )
    },
    fn() raise @moonstatsd.EncodeError {
      @moonstatsd.encode("x", Counter(0.0 / 0.0))
    },
    fn() raise @moonstatsd.EncodeError { @moonstatsd.encode("x", Timer(-1.0)) },
    fn() raise @moonstatsd.EncodeError { @moonstatsd.encode("", Counter(1.0)) },
  ]
  for f in bad {
    let rejected = try {
      ignore(f())
      false
    } catch {
      _ => true
    }
    assert_true(rejected)
  }
}

///|
test "UTF8 and complete datagram boundaries" {
  let a = @moonstatsd.encode("中", Counter(1.0), max_bytes=7)
  assert_eq(a.bytes(), b"\xe4\xb8\xad:1|c")
  let rejected = try {
    ignore(@moonstatsd.encode("中", Counter(1.0), max_bytes=6))
    false
  } catch {
    _ => true
  }
  assert_true(rejected)
  let b = @moonstatsd.encode("b", Counter(2.0))
  assert_eq(@moonstatsd.pack([a, b], max_bytes=13), [b"\xe4\xb8\xad:1|c\nb:2|c"])
  assert_eq(@moonstatsd.pack([a, b], max_bytes=12), [a.bytes(), b.bytes()])
  assert_eq(@moonstatsd.pack([]), [])
  assert_true(
    try {
      ignore(@moonstatsd.pack([a], max_bytes=6))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@moonstatsd.pack([a, b], max_total_bytes=11))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "deterministic sampling threshold" {
  assert_true(@moonstatsd.sampled(0.5, 0.499))
  assert_false(@moonstatsd.sampled(0.5, 0.5))
  assert_true(@moonstatsd.sampled(1.0, 0.999))
  assert_true(
    try {
      ignore(@moonstatsd.sampled(0.0, 0.5))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@moonstatsd.sampled(0.5, 1.0))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "signed zero delta and tag byte budgets" {
  assert_eq(@moonstatsd.encode("q", GaugeDelta(-0.0)).bytes(), b"q:+0|g")
  assert_eq(@moonstatsd.encode("q", Gauge(-0.0)).bytes(), b"q:0|g")
  assert_true(
    try {
      ignore(
        @moonstatsd.encode(
          "x",
          Counter(1.0),
          mode=DogStatsD,
          tags=["中文", "中文"],
          max_bytes=10,
        ),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@moonstatsd.encode("x", Counter(1.0), prefix="bad\r"))
      false
    } catch {
      _ => true
    },
  )
}

///|
test "DogStatsD naming policy and relative gauge restriction" {
  assert_true(
    try {
      ignore(@moonstatsd.encode("中文", Counter(1.0), mode=DogStatsD))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@moonstatsd.encode("a-b", Counter(1.0), mode=DogStatsD))
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(
        @moonstatsd.encode("x", Counter(1.0), mode=DogStatsD, prefix="bad-"),
      )
      false
    } catch {
      _ => true
    },
  )
  assert_true(
    try {
      ignore(@moonstatsd.encode("x", GaugeDelta(-1.0), mode=DogStatsD))
      false
    } catch {
      _ => true
    },
  )
  assert_eq(
    @moonstatsd.encode("valid_1.a", Gauge(7.0), mode=DogStatsD).bytes(),
    b"valid_1.a:7|g",
  )
}
