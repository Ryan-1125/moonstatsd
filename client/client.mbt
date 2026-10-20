///|
pub(all) suberror ClientError {
  Closed
  QueueFull
  InvalidConfig(String)
} derive(Debug)

///|
pub extend ClientError with @debug.Debug::{to_repr}

///|
pub(all) enum Admission {
  Enqueued
  SampledOut
} derive(Eq, Debug)

///|
pub extend Admission with Eq::{equal, not_equal}

///|
pub extend Admission with @debug.Debug::{to_repr}

///|
/// Cumulative local observations, never a collector delivery acknowledgement.
pub struct Stats {
  enqueued : Int64
  sampled_out : Int64
  queue_full : Int64
  submitted : Int64
  send_errors : Int64
  last_send_error : String?
  dropped : Int64
  pending : Int64
  closed : Bool
} derive(Debug)

///|
pub extend Stats with @debug.Debug::{to_repr}

///|
/// Cooperative tasks in one async event loop only. Not OS thread safe.
pub struct Client {
  priv mode : @codec.Mode
  priv prefix : String
  priv tags : Array[String]
  priv max_bytes : Int32
  priv capacity : Int32
  priv interval_ms : Int32
  priv timeout_ms : Int32
  priv draw : () -> Double
  priv queue : @deque.Deque[@codec.Message]
  priv wake : @async.CondVar
  priv changed : @async.CondVar
  priv mut worker : @async.Task[Unit]?
  priv mut requested : Bool
  priv mut state : Int32
  priv mut accepted : Int64
  priv mut done : Int64
  priv mut sampled_out : Int64
  priv mut queue_full : Int64
  priv mut submitted : Int64
  priv mut send_errors : Int64
  priv mut last_send_error : String?
  priv mut dropped : Int64
}

///|
pub fn Client::stats(self : Client) -> Stats {
  {
    enqueued: self.accepted,
    sampled_out: self.sampled_out,
    queue_full: self.queue_full,
    submitted: self.submitted,
    send_errors: self.send_errors,
    last_send_error: self.last_send_error,
    dropped: self.dropped,
    pending: self.accepted - self.done,
    closed: self.state == 2,
  }
}

///|
/// Synchronous admission is atomic between cooperative tasks. Full queue rejects newest.
/// Validation precedes sampling; a sampled-out invalid metric is still an error.
pub fn Client::record(
  self : Client,
  name : String,
  metric : @codec.Metric,
  tags~ : Array[String] = [],
  rate~ : Double = 1.0,
) -> Admission raise {
  if self.state != 0 {
    raise Closed
  }
  let message = @codec.encode(
    name,
    metric,
    mode=self.mode,
    prefix=self.prefix,
    fixed_tags=self.tags,
    tags~,
    rate~,
    max_bytes=self.max_bytes,
  )
  if rate < 1 && !@codec.sampled(rate, (self.draw)()) {
    self.sampled_out += 1
    return SampledOut
  }
  if self.accepted - self.done >= self.capacity.to_int64() {
    self.queue_full += 1
    raise QueueFull
  }
  self.queue.push_back(message)
  self.accepted += 1
  if self.accepted - self.done == self.capacity.to_int64() {
    self.wake.signal()
  }
  Enqueued
}

///|
/// Barrier for admissions preceding this call. Returns cumulative local outcomes.
/// Timeout/caller cancellation stops this waiter, not the sending task.
pub async fn Client::flush(
  self : Client,
  timeout_ms~ : Int32 = self.timeout_ms,
) -> Stats {
  if timeout_ms < 1 {
    raise InvalidConfig("timeout_ms must be positive")
  }
  let target = self.accepted
  self.requested = true
  self.wake.signal()
  @async.with_timeout(timeout_ms, () => {
    while self.done < target {
      self.changed.wait()
    }
  })
  self.stats()
}

///|
/// Reject new records immediately; bounded drain. Cancellation/timeout cancels the
/// sender and drops remaining admissions. Repeated close returns the same counters.
pub async fn Client::close(
  self : Client,
  timeout_ms~ : Int32 = self.timeout_ms,
) -> Stats {
  if timeout_ms < 1 {
    raise InvalidConfig("timeout_ms must be positive")
  }
  if self.state == 0 {
    self.state = 1
  }
  self.wake.signal()
  errdefer (if self.worker is Some(task) { task.cancel() })
  @async.with_timeout(timeout_ms, () => {
    while self.state != 2 {
      self.changed.wait()
    }
  })
  self.stats()
}

///|
async fn Client::send_loop(self : Client, socket : @socket.UdpClient) -> Unit {
  defer {
    socket.close()
    self.dropped += self.accepted - self.done
    self.done = self.accepted
    self.queue.clear()
    self.state = 2
    self.changed.broadcast()
  }
  while true {
    // Wake on explicit barrier/full queue, or bounded periodic timer.
    if self.state == 0 &&
      !self.requested &&
      self.accepted - self.done < self.capacity.to_int64() {
      ignore(@async.with_timeout_opt(self.interval_ms, () => self.wake.wait()))
    }
    self.requested = false
    while self.queue.pop_front() is Some(first) {
      let mut bytes = first.bytes()
      let mut count = 1L
      while self.queue.front() is Some(next) &&
            bytes.length() + 1 + next.bytes().length() <= self.max_bytes {
        ignore(self.queue.pop_front())
        bytes = bytes + b"\n" + next.bytes()
        count += 1
      }
      try {
        @async.with_timeout(self.timeout_ms, () => socket.send(bytes))
        self.submitted += count
      } catch {
        err => {
          if @async.is_cancellation_error(err) {
            raise err
          }
          self.send_errors += 1
          self.last_send_error = Some(err.to_string())
          self.dropped += count
        }
      }
      self.done += count
      self.changed.broadcast()
      // Yield even if the platform send completed synchronously, to avoid starvation.
      @async.pause()
    }
    if self.state != 0 {
      break
    }
  }
}

///|
/// Structured lifetime: callback success closes/drains; failure cancels/drops.
/// Captured Client handles become Closed after scope exit. Fixed tags are copied.
/// Capacity counts queued AND in-flight metrics. Maximum buffered wire storage is
/// approximately capacity*max_bytes plus one datagram and encoder workspace.
pub async fn[T] with_client(
  addr : @socket.Addr,
  work : async (Client) -> T,
  mode~ : @codec.Mode = StatsD,
  prefix~ : String = "",
  fixed_tags~ : Array[String] = [],
  capacity~ : Int32 = 256,
  max_bytes~ : Int32 = 512,
  interval_ms~ : Int32 = 100,
  timeout_ms~ : Int32 = 1000,
  random? : () -> Double,
) -> T {
  if capacity < 1 || capacity > 65536 {
    raise InvalidConfig("capacity must be in 1..65536")
  }
  if max_bytes < 1 || max_bytes > 65507 {
    raise InvalidConfig("max_bytes must be in 1..65507")
  }
  if interval_ms < 1 {
    raise InvalidConfig("interval_ms must be positive")
  }
  if timeout_ms < 1 {
    raise InvalidConfig("timeout_ms must be positive")
  }
  if capacity > 16777216 / max_bytes {
    raise InvalidConfig("capacity times max_bytes exceeds 16MiB wire budget")
  }
  if addr.port() == 0 {
    raise InvalidConfig("destination UDP port must be nonzero")
  }
  let tags = fixed_tags.copy()
  // Validate configuration even if callback emits no metrics.
  ignore(
    @codec.encode(
      "config",
      Counter(0.0),
      mode~,
      prefix~,
      fixed_tags=tags,
      max_bytes=65507,
    ),
  )
  let draw = match random {
    Some(f) => f
    None => {
      let seed = @env.rand(32).unwrap_or_else(() => {
        raise InvalidConfig("system entropy unavailable; supply random source")
      })
      let rng = @random.Rand::chacha8(seed~)
      () => rng.double()
    }
  }
  let socket = @socket.UdpClient(addr)
  defer socket.close()
  let client : Client = {
    mode,
    prefix,
    tags,
    max_bytes,
    capacity,
    interval_ms,
    timeout_ms,
    draw,
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
  @async.with_task_group(group => {
    let task = group.spawn(() => client.send_loop(socket), no_wait=true)
    client.worker = Some(task)
    defer task.cancel()
    let result = work(client)
    ignore(client.close())
    result
  })
}
