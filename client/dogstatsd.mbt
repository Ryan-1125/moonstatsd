///|
pub fn Scope::event(
  self : Scope,
  title : String,
  text : String,
  timestamp? : Int64,
  hostname? : String,
  aggregation_key? : String,
  source_type? : String,
  priority~ : @codec.EventPriority = Normal,
  alert~ : @codec.AlertType = Info,
  tags~ : Array[String] = [],
) -> Admission raise {
  if self.owner.state != 0 {
    raise Closed
  }
  if self.owner.mode != DogStatsD {
    raise InvalidConfig("events require DogStatsD")
  }
  self.owner.admit(
    @codec.encode_event(
      title,
      text,
      timestamp?,
      hostname?,
      aggregation_key?,
      source_type?,
      priority~,
      alert~,
      tags=self.tags + tags,
      max_bytes=self.owner.max_bytes,
    ),
  )
}

///|
pub fn Scope::service_check(
  self : Scope,
  name : String,
  status : @codec.CheckStatus,
  timestamp? : Int64,
  hostname? : String,
  message? : String,
  tags~ : Array[String] = [],
) -> Admission raise {
  if self.owner.state != 0 {
    raise Closed
  }
  if self.owner.mode != DogStatsD {
    raise InvalidConfig("service checks require DogStatsD")
  }
  self.owner.admit(
    @codec.encode_check(
      self.prefix + name,
      status,
      timestamp?,
      hostname?,
      message?,
      tags=self.tags + tags,
      max_bytes=self.owner.max_bytes,
    ),
  )
}

///|
pub fn Scope::record_values(
  self : Scope,
  name : String,
  values : Array[@codec.Metric],
  tags~ : Array[String] = [],
  rate~ : Double = 1.0,
) -> Admission raise {
  if self.owner.state != 0 {
    raise Closed
  }
  if self.owner.mode != DogStatsD {
    raise InvalidConfig("value packing requires DogStatsD")
  }
  let message = @codec.encode_values(
    name,
    values,
    prefix=self.prefix,
    tags=self.tags + tags,
    rate~,
    max_bytes=self.owner.max_bytes,
  )
  if rate < 1 && !@codec.sampled(rate, (self.owner.draw)()) {
    self.owner.sampled_out += 1
    return SampledOut
  }
  self.owner.admit(message)
}
