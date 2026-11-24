///|
struct AggregateEntry {
  key : String
  name : String
  tags : Array[String]
  mut metric : Metric
}

///|
/// Explicit bounded aggregation window. Counter sums, gauge last, set deduplicates;
/// observations (timer/histogram/distribution) remain separate to preserve samples.
pub struct AggregateBuffer {
  priv entries : Array[AggregateEntry]
  priv capacity : Int32
  priv max_bytes : Int32
}

///|
pub fn AggregateBuffer::new(
  capacity~ : Int32 = 256,
  max_bytes~ : Int32 = 512,
) -> AggregateBuffer raise EncodeError {
  if capacity < 1 ||
    capacity > 65536 ||
    max_bytes < 1 ||
    max_bytes > 65507 ||
    capacity > 16777216 / max_bytes {
    raise Invalid("aggregation budget")
  }
  { entries: [], capacity, max_bytes, }
}

///|
pub fn AggregateBuffer::length(self : AggregateBuffer) -> Int32 {
  self.entries.length()
}

///|
pub fn AggregateBuffer::clear(self : AggregateBuffer) -> Unit {
  self.entries.clear()
}

///|
pub fn AggregateBuffer::record(
  self : AggregateBuffer,
  name : String,
  metric : Metric,
  tags~ : Array[String] = [],
) -> Unit raise EncodeError {
  let encoded = encode(
    name,
    metric,
    mode=DogStatsD,
    tags~,
    max_bytes=self.max_bytes,
  )
  let (kind, identity) = match metric {
    Counter(_) => ("c", "")
    Gauge(_) => ("g", "")
    Set(value) => ("s", value)
    Timer(_) => ("ms", "")
    Histogram(_) => ("h", "")
    Distribution(_) => ("d", "")
    _ => ("observation", "")
  }
  let key = kind +
    ":" +
    identity +
    ":" +
    (@utf8.decode(
      encode(
        name,
        Counter(0.0),
        mode=DogStatsD,
        tags~,
        max_bytes=self.max_bytes,
      ).bytes(),
    ) catch {
      _ => raise Invalid("UTF-8")
    })
  if kind == "c" || kind == "g" || kind == "s" {
    for entry in self.entries {
      if entry.key == key {
        match (entry.metric, metric) {
          (Counter(a), Counter(b)) => {
            let sum = a + b
            finite(sum)
            ignore(
              encode(
                name,
                Counter(sum),
                mode=DogStatsD,
                tags~,
                max_bytes=self.max_bytes,
              ),
            )
            entry.metric = Counter(sum)
          }
          (Gauge(_), Gauge(value)) => entry.metric = Gauge(value)
          _ => ()
        }
        return
      }
    }
  }
  ignore(encoded)
  if self.entries.length() >= self.capacity {
    raise Invalid("aggregation capacity exhausted; submit or clear window")
  }
  self.entries.push({ key, name, tags: tags.copy(), metric, })
}

///|
/// Snapshot without clearing: callers can retry submission after backpressure.
pub fn AggregateBuffer::messages(
  self : AggregateBuffer,
  prefix~ : String = "",
  fixed_tags~ : Array[String] = [],
  max_bytes~ : Int32 = self.max_bytes,
) -> Array[Message] raise EncodeError {
  let out : Array[Message] = []
  let mut i = 0
  while i < self.entries.length() {
    let entry = self.entries[i]
    let mut current = encode(
      entry.name,
      entry.metric,
      mode=DogStatsD,
      prefix~,
      fixed_tags~,
      tags=entry.tags,
      max_bytes~,
    )
    let values = [entry.metric]
    i += 1
    let packable = match entry.metric {
      Timer(_) | Histogram(_) | Distribution(_) => true
      _ => false
    }
    if packable {
      while i < self.entries.length() && self.entries[i].key == entry.key {
        values.push(self.entries[i].metric)
        let candidate = Some(
          encode_values(
            entry.name,
            values,
            prefix~,
            tags=fixed_tags + entry.tags,
            max_bytes~,
          ),
        ) catch {
          TooLarge(_, _) => None
          err => raise err
        }
        match candidate {
          Some(message) => {
            current = message
            i += 1
          }
          None => break
        }
      }
    }
    out.push(current)
  }
  out
}
