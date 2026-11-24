///|
fn main raise {
  let cases : Array[(String, @codec.Metric)] = [
    ("count", Counter(2.0)),
    ("gauge", Gauge(3.0)),
    ("timer", Timer(12.5)),
    ("set", Set("abc")),
    ("histogram", Histogram(4.0)),
    ("distribution", Distribution(5.0)),
  ]
  for (name, metric) in cases {
    let message = @codec.encode(
      name,
      metric,
      mode=DogStatsD,
      prefix="svc.",
      fixed_tags=["env:test"],
      tags=["route:home"],
    ) catch {
      _ => abort("invalid fixture")
    }
    println(@utf8.decode(message.bytes()))
  }
  println(
    @utf8.decode(
      @codec.encode_event(
        "发布",
        "line1\nline2",
        timestamp=1700000000L,
        hostname="node",
        aggregation_key="deploy",
        source_type="ci",
        alert=Success,
        tags=["env:test", "route:home"],
      ).bytes(),
    ),
  )
  println(
    @utf8.decode(
      @codec.encode_check(
        "svc.health",
        Critical,
        timestamp=1700000000L,
        hostname="node",
        message="line1\nm:ready",
        tags=["env:test", "route:home"],
      ).bytes(),
    ),
  )
}
