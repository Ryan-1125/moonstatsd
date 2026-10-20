///|
async fn main {
  let addr = @socket.Addr::parse(
    @env.get_env_var("MOONSTATSD_ADDR").unwrap_or("127.0.0.1:19126"),
  )
  @client.with_client(
    addr,
    c => {
      ignore(c.record("count", Counter(2.0), rate=0.5))
      ignore(c.record("queue", Gauge(10.0)))
      ignore(c.record("queue", GaugeDelta(-3.0)))
      ignore(c.record("time", Timer(250.0)))
      ignore(c.record("unique", Set("alice")))
      ignore(c.record("unique", Set("alice")))
      ignore(c.record("unique", Set("bob")))
      let report = c.close()
      println("submitted=\{report.submitted} errors=\{report.send_errors}")
    },
    prefix="plain.",
    random=() => 0.1,
  )
}
