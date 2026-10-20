///|
pub(all) enum Mode {
  StatsD
  DogStatsD
} derive(Eq, Debug)

///|
pub(all) enum Metric {
  Counter(Double)
  Gauge(Double)
  GaugeDelta(Double)
  Timer(Double)
  Set(String)
  Histogram(Double)
  Distribution(Double)
} derive(Debug)

///|
pub(all) suberror EncodeError {
  Invalid(String)
  TooLarge(Int32, Int32)
} derive(Debug)

///|
/// Validated, indivisible wire message. Negative absolute gauges are rejected.
pub struct Message {
  priv wire : Bytes
}

///|
pub fn Message::bytes(self : Message) -> Bytes {
  self.wire
}

///|
fn field(
  s : String,
  forbidden : String,
  empty~ : Bool = false,
) -> Unit raise EncodeError {
  if !empty && s.is_empty() {
    raise Invalid("empty field")
  }
  for c in s {
    if c.to_int() < 32 || c.to_int() == 127 || forbidden.contains(c.to_string()) {
      raise Invalid("field delimiter or control character")
    }
  }
}

///|
fn finite(v : Double) -> Unit raise EncodeError {
  if v.is_nan() || v.is_inf() {
    raise Invalid("non-finite number")
  }
}

///|
/// Rate validation is separate from random selection. draw must be uniform [0,1).
pub fn sampled(rate : Double, draw : Double) -> Bool raise EncodeError {
  finite(rate)
  finite(draw)
  if rate <= 0 || rate > 1 || draw < 0 || draw >= 1 {
    raise Invalid("sampling range")
  }
  draw < rate
}

///|
/// Tags: fixed first, then call tags; duplicate keys are rejected, including bare tags.
/// prefix is concatenated exactly (include a trailing dot if desired).
/// Gauge and Set require rate=1. Timer is milliseconds. No random selection here.
pub fn encode(
  name : String,
  metric : Metric,
  mode~ : Mode = StatsD,
  prefix~ : String = "",
  fixed_tags~ : Array[String] = [],
  tags~ : Array[String] = [],
  rate~ : Double = 1.0,
  max_bytes~ : Int32 = 512,
) -> Message raise EncodeError {
  if max_bytes < 1 || max_bytes > 65507 {
    raise Invalid("datagram limit 1..65507")
  }
  // Bound individual inputs before concatenation. UTF-8 is checked again on final output.
  if name.length() > max_bytes ||
    prefix.length() > max_bytes ||
    tags.length() + fixed_tags.length() > max_bytes {
    raise TooLarge(max_bytes + 1, max_bytes)
  }
  field(name, ":|,@# ")
  field(prefix, ":|,@# ", empty=true)
  finite(rate)
  if rate <= 0 || rate > 1 {
    raise Invalid("rate must be in (0,1]")
  }
  let (value, kind) = match metric {
    Set(s) => {
      field(s, ":|")
      if s.length() > max_bytes {
        raise TooLarge(s.length(), max_bytes)
      }
      (s, "s")
    }
    Counter(v) => {
      finite(v)
      (v.to_string(), "c")
    }
    Gauge(v) => {
      finite(v)
      if v < 0 {
        raise Invalid(
          "negative absolute gauge is unsupported; use explicit delta or reject at caller",
        )
      }
      (if v == 0 { "0" } else { v.to_string() }, "g")
    }
    GaugeDelta(v) => {
      finite(v)
      (if v >= 0 { "+" + v.to_string() } else { v.to_string() }, "g")
    }
    Timer(v) => {
      finite(v)
      if v < 0 {
        raise Invalid("negative duration")
      }
      (v.to_string(), "ms")
    }
    Histogram(v) => {
      finite(v)
      if mode != DogStatsD {
        raise Invalid("histogram needs DogStatsD")
      }
      (v.to_string(), "h")
    }
    Distribution(v) => {
      finite(v)
      if mode != DogStatsD {
        raise Invalid("distribution needs DogStatsD")
      }
      (v.to_string(), "d")
    }
  }
  match metric {
    Gauge(_) | GaugeDelta(_) | Set(_) =>
      if rate != 1 {
        raise Invalid("sampling unsupported for gauge/set")
      }
    _ => ()
  }
  let all_tags = fixed_tags + tags
  if mode == StatsD && !all_tags.is_empty() {
    raise Invalid("tags need DogStatsD")
  }
  let keys : Array[String] = []
  let mut tag_bytes = 0
  for tag in all_tags {
    if tag.length() > max_bytes {
      raise TooLarge(tag.length(), max_bytes)
    }
    tag_bytes += @utf8.encode(tag).length() + 1
    if tag_bytes > max_bytes {
      raise TooLarge(tag_bytes, max_bytes)
    }
    field(tag, "|, ")
    let key = tag.split(":").to_array()[0].to_owned()
    field(key, ":|, ")
    if keys.contains(key) {
      raise Invalid("duplicate tag key")
    }
    keys.push(key)
  }
  let mut text = prefix + name + ":" + value + "|" + kind
  if rate < 1 {
    text += "|@" + rate.to_string()
  }
  if !all_tags.is_empty() {
    text += "|#" + all_tags.join(",")
  }
  let wire = @utf8.encode(text)
  if wire.length() > max_bytes {
    raise TooLarge(wire.length(), max_bytes)
  }
  { wire, }
}

///|
/// Batch complete messages; no splitting. Bound both datagram size and total input bytes.
pub fn pack(
  messages : Array[Message],
  max_bytes~ : Int32 = 512,
  max_total_bytes~ : Int32 = 1048576,
) -> Array[Bytes] raise EncodeError {
  if max_bytes < 1 || max_bytes > 65507 || max_total_bytes < 1 {
    raise Invalid("invalid pack limit")
  }
  let out : Array[Bytes] = []
  let mut current = b""
  let mut total = 0
  for message in messages {
    let wire = message.wire
    if wire.length() > max_bytes {
      raise TooLarge(wire.length(), max_bytes)
    }
    if wire.length() > max_total_bytes - total {
      raise Invalid("batch total byte limit")
    }
    total += wire.length()
    if current.length() == 0 {
      current = wire
    } else if current.length() + 1 + wire.length() <= max_bytes {
      current = current + b"\n" + wire
    } else {
      out.push(current)
      current = wire
    }
  }
  if current.length() > 0 {
    out.push(current)
  }
  out
}

///|
pub extend Mode with Eq::{equal, not_equal}

///|
pub extend Mode with @debug.Debug::{to_repr}

///|
pub extend Metric with @debug.Debug::{to_repr}

///|
pub extend EncodeError with @debug.Debug::{to_repr}
