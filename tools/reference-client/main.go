package main

import (
	"fmt"
	"github.com/DataDog/datadog-go/v5/statsd"
	"sync"
)

type wireWriter struct{ mu sync.Mutex }

func (w *wireWriter) Write(p []byte) (int, error) {
	w.mu.Lock()
	defer w.mu.Unlock()
	fmt.Println(string(p))
	return len(p), nil
}
func (w *wireWriter) Close() error { return nil }
func main() {
	c, err := statsd.NewWithWriter(&wireWriter{}, statsd.WithoutClientSideAggregation(), statsd.WithoutTelemetry(), statsd.WithoutOriginDetection(), statsd.WithMaxMessagesPerPayload(1), statsd.WithWorkersCount(1), statsd.WithNamespace("svc."), statsd.WithTags([]string{"env:test"}))
	if err != nil {
		panic(err)
	}
	check := func(err error) {
		if err != nil {
			panic(err)
		}
	}
	tags := []string{"route:home"}
	check(c.Count("count", 2, tags, 1))
	check(c.Gauge("gauge", 3, tags, 1))
	check(c.TimeInMilliseconds("timer", 12.5, tags, 1))
	check(c.Set("set", "abc", tags, 1))
	check(c.Histogram("histogram", 4, tags, 1))
	check(c.Distribution("distribution", 5, tags, 1))
	check(c.Flush())
	check(c.Close())
}
