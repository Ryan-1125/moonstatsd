///|
pub(all) enum CheckStatus {
  Ok
  Warning
  Critical
  Unknown
}

///|
pub(all) enum EventPriority {
  Normal
  Low
}

///|
pub(all) enum AlertType {
  Info
  ErrorAlert
  WarningAlert
  Success
}

///|
fn bounded_message(
  text : String,
  max_bytes : Int32,
) -> Message raise EncodeError {
  if max_bytes < 1 || max_bytes > 65507 {
    raise Invalid("datagram limit 1..65507")
  }
  let wire = @utf8.encode(text)
  if wire.length() > max_bytes {
    raise TooLarge(wire.length(), max_bytes)
  }
  { wire, }
}

///|
fn dog_tags(
  tags : Array[String],
  max_bytes : Int32,
) -> String raise EncodeError {
  // Reuse the same duplicate-key, injection and UTF-8 budget rules as metrics.
  ignore(encode("x", Counter(0.0), mode=DogStatsD, tags~, max_bytes~))
  if tags.is_empty() {
    ""
  } else {
    "|#" + tags.join(",")
  }
}

///|
fn escaped_text(
  text : String,
  max_bytes : Int32,
  allow_pipe~ : Bool = false,
) -> String raise EncodeError {
  if text.length() > max_bytes {
    raise TooLarge(text.length(), max_bytes)
  }
  let escaped = text.replace(old="\n", new="\\n")
  field(escaped, if allow_pipe { "" } else { "|" }, empty=true)
  escaped
}

///|
fn metadata(
  timestamp : Int64?,
  hostname : String?,
  max_bytes : Int32,
) -> String raise EncodeError {
  let mut text = ""
  if timestamp is Some(t) {
    if t < 0 {
      raise Invalid("negative Unix timestamp")
    }
    text += "|d:" + t.to_string()
  }
  if hostname is Some(host) {
    if host.length() > max_bytes {
      raise TooLarge(host.length(), max_bytes)
    }
    field(host, "|")
    text += "|h:" + host
  }
  text
}

///|
/// DogStatsD event; lengths measure escaped UTF-8 payload bytes. No sampling.
pub fn encode_event(
  title : String,
  text : String,
  timestamp? : Int64,
  hostname? : String,
  aggregation_key? : String,
  source_type? : String,
  priority~ : EventPriority = Normal,
  alert~ : AlertType = Info,
  tags~ : Array[String] = [],
  max_bytes~ : Int32 = 512,
) -> Message raise EncodeError {
  if max_bytes < 1 || max_bytes > 65507 {
    raise Invalid("datagram limit 1..65507")
  }
  let title = escaped_text(title, max_bytes, allow_pipe=true)
  if title.is_empty() {
    raise Invalid("empty event title")
  }
  let text = escaped_text(text, max_bytes, allow_pipe=true)
  let mut out = "_e{" +
    @utf8.encode(title).length().to_string() +
    "," +
    @utf8.encode(text).length().to_string() +
    "}:" +
    title +
    "|" +
    text
  out += metadata(timestamp, hostname, max_bytes)
  if aggregation_key is Some(key) {
    if key.length() > max_bytes {
      raise TooLarge(key.length(), max_bytes)
    }
    field(key, "|")
    out += "|k:" + key
  }
  out += "|p:" +
    (match priority {
      Normal => "normal"
      Low => "low"
    })
  if source_type is Some(source) {
    if source.length() > max_bytes {
      raise TooLarge(source.length(), max_bytes)
    }
    field(source, "|")
    out += "|s:" + source
  }
  out += "|t:" +
    (match alert {
      Info => "info"
      ErrorAlert => "error"
      WarningAlert => "warning"
      Success => "success"
    })
  out += dog_tags(tags, max_bytes)
  bounded_message(out, max_bytes)
}

///|
/// DogStatsD service check. Message is always the last optional field.
pub fn encode_check(
  name : String,
  status : CheckStatus,
  timestamp? : Int64,
  hostname? : String,
  message? : String,
  tags~ : Array[String] = [],
  max_bytes~ : Int32 = 512,
) -> Message raise EncodeError {
  if max_bytes < 1 || max_bytes > 65507 {
    raise Invalid("datagram limit 1..65507")
  }
  if name.length() > max_bytes {
    raise TooLarge(name.length(), max_bytes)
  }
  field(name, "|")
  let code = match status {
    Ok => "0"
    Warning => "1"
    Critical => "2"
    Unknown => "3"
  }
  let mut out = "_sc|" +
    name +
    "|" +
    code +
    metadata(timestamp, hostname, max_bytes) +
    dog_tags(tags, max_bytes)
  if message is Some(text) {
    out += "|m:" + escaped_text(text, max_bytes).replace(old="m:", new="m\\:")
  }
  bounded_message(out, max_bytes)
}

///|
/// DogStatsD v1.1 numeric value packing. Set and relative gauge cannot be packed.
pub fn encode_values(
  name : String,
  metrics : Array[Metric],
  prefix~ : String = "",
  tags~ : Array[String] = [],
  rate~ : Double = 1.0,
  max_bytes~ : Int32 = 512,
) -> Message raise EncodeError {
  if metrics.is_empty() || metrics.length() > max_bytes {
    raise Invalid("invalid value count")
  }
  let first = encode(
    name,
    metrics[0],
    mode=DogStatsD,
    prefix~,
    tags~,
    rate~,
    max_bytes~,
  )
  let parts = (@utf8.decode(first.bytes()) catch {
      _ => raise Invalid("internal UTF-8")
    })
    .split("|")
    .to_array()
  let head = parts[0].to_owned()
  let kind = parts[1].to_owned()
  if kind == "s" {
    raise Invalid("sets do not support value packing")
  }
  let mut values = head
  for i = 1; i < metrics.length(); i = i + 1 {
    let encoded = encode(
      name,
      metrics[i],
      mode=DogStatsD,
      prefix~,
      tags~,
      rate~,
      max_bytes~,
    )
    let other = (@utf8.decode(encoded.bytes()) catch {
        _ => raise Invalid("internal UTF-8")
      })
      .split("|")
      .to_array()
    if other[1] != kind {
      raise Invalid("mixed packed metric types")
    }
    let pair = other[0].split(":").to_array()
    values += ":" + pair[1].to_owned()
    if values.length() > max_bytes {
      raise TooLarge(values.length(), max_bytes)
    }
  }
  let suffix = parts[1:].map(x => x.to_owned()).join("|")
  bounded_message(values + "|" + suffix, max_bytes)
}
