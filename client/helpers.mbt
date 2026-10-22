///|
/// One failed local datagram send. Notification occurs after accounting, without retries.
pub struct SendFailure {
  message : String
  metrics : Int64
  bytes : Int32
  stats : Stats
}

///|
/// A lightweight namespace/tag view sharing its owner's sender, capacity and lifetime.
pub struct Scope {
  priv owner : Client
  priv prefix : String
  priv tags : Array[String]
}

///|
fn make_scope(
  owner : Client,
  prefix : String,
  tags : Array[String],
) -> Scope raise {
  if owner.state != 0 {
    raise Closed
  }
  ignore(
    @codec.encode(
      "x",
      Counter(0.0),
      mode=owner.mode,
      prefix~,
      fixed_tags=tags,
      max_bytes=owner.max_bytes,
    ),
  )
  { owner, prefix, tags: tags.copy(), }
}

///|
/// Append prefix verbatim and snapshot extra tags; duplicate keys are rejected.
pub fn Client::scope(
  self : Client,
  prefix~ : String = "",
  tags~ : Array[String] = [],
) -> Scope raise {
  if prefix.length() > self.max_bytes || tags.length() > self.max_bytes {
    raise InvalidConfig("scope configuration exceeds datagram budget")
  }
  make_scope(self, self.prefix + prefix, self.tags + tags)
}

///|
pub fn Scope::scope(
  self : Scope,
  prefix~ : String = "",
  tags~ : Array[String] = [],
) -> Scope raise {
  if prefix.length() > self.owner.max_bytes ||
    tags.length() > self.owner.max_bytes {
    raise InvalidConfig("scope configuration exceeds datagram budget")
  }
  make_scope(self.owner, self.prefix + prefix, self.tags + tags)
}

///|
pub fn Scope::record(
  self : Scope,
  name : String,
  metric : @codec.Metric,
  tags~ : Array[String] = [],
  rate~ : Double = 1.0,
) -> Admission raise {
  self.owner.record_with(name, metric, self.prefix, self.tags, tags~, rate~)
}

///|
/// One-shot elapsed-time observation. Default SDK clock is epoch milliseconds;
/// backwards clock movement is rejected. A caller may inject a monotonic clock.
pub struct Stopwatch {
  priv scope : Scope
  priv name : String
  priv tags : Array[String]
  priv rate : Double
  priv clock : () -> UInt64
  priv started : UInt64
  priv mut stopped : Bool
}

///|
pub fn Scope::start_timer(
  self : Scope,
  name : String,
  tags~ : Array[String] = [],
  rate~ : Double = 1.0,
  clock~ : () -> UInt64 = @env.now,
) -> Stopwatch raise {
  if self.owner.state != 0 {
    raise Closed
  }
  ignore(
    @codec.encode(
      name,
      Timer(0.0),
      mode=self.owner.mode,
      prefix=self.prefix,
      fixed_tags=self.tags,
      tags~,
      rate~,
      max_bytes=self.owner.max_bytes,
    ),
  )
  {
    scope: self,
    name,
    tags: tags.copy(),
    rate,
    clock,
    started: clock(),
    stopped: false,
  }
}

///|
pub fn Client::start_timer(
  self : Client,
  name : String,
  tags~ : Array[String] = [],
  rate~ : Double = 1.0,
  clock~ : () -> UInt64 = @env.now,
) -> Stopwatch raise {
  self.scope().start_timer(name, tags~, rate~, clock~)
}

///|
/// First stop attempt consumes the timer, including queue-full/closed/error outcomes.
/// No implicit recording on errors or cancellation; callers explicitly choose stop.
pub fn Stopwatch::stop(self : Stopwatch) -> Admission raise {
  if self.stopped {
    raise TimerStopped
  }
  self.stopped = true
  let finished = (self.clock)()
  if finished < self.started {
    raise InvalidConfig("timer clock moved backwards")
  }
  self.scope.record(
    self.name,
    Timer((finished - self.started).to_double()),
    tags=self.tags,
    rate=self.rate,
  )
}
