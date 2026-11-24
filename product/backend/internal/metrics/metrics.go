package metrics

import (
	"context"
	"sync"
	"time"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/metric"
)

type instruments struct {
	eventsAppended metric.Int64Counter

	commandHandled  metric.Int64Counter
	commandDuration metric.Float64Histogram

	projectionErrors metric.Int64Counter

	bookingsCreated   metric.Int64Counter
	bookingsCancelled metric.Int64Counter
	bookingsRejected  metric.Int64Counter

	authCodesIssued metric.Int64Counter
	authLogins      metric.Int64Counter

	rateLimitRejected metric.Int64Counter

	sidecarRequests metric.Int64Counter
	sidecarDuration metric.Float64Histogram

	emailSent metric.Int64Counter
}

var (
	once sync.Once
	inst instruments
)

func get() *instruments {
	once.Do(func() {
		m := otel.Meter("booking")
		inst.eventsAppended, _ = m.Int64Counter("events.appended",
			metric.WithDescription("Events appended to the event store."))
		inst.commandHandled, _ = m.Int64Counter("commands.handled",
			metric.WithDescription("Commands handled by the command service."))
		inst.commandDuration, _ = m.Float64Histogram("commands.duration",
			metric.WithUnit("s"),
			metric.WithDescription("Command handling duration in seconds."))
		inst.projectionErrors, _ = m.Int64Counter("projection.errors",
			metric.WithDescription("Projection apply errors."))
		inst.bookingsCreated, _ = m.Int64Counter("bookings.created",
			metric.WithDescription("Bookings created."))
		inst.bookingsCancelled, _ = m.Int64Counter("bookings.cancelled",
			metric.WithDescription("Bookings cancelled."))
		inst.bookingsRejected, _ = m.Int64Counter("bookings.rejected",
			metric.WithDescription("Booking attempts rejected."))
		inst.authCodesIssued, _ = m.Int64Counter("auth.codes_issued",
			metric.WithDescription("Login codes issued."))
		inst.authLogins, _ = m.Int64Counter("auth.logins",
			metric.WithDescription("Login outcomes."))
		inst.rateLimitRejected, _ = m.Int64Counter("ratelimit.rejected",
			metric.WithDescription("Requests rejected by rate limiters."))
		inst.sidecarRequests, _ = m.Int64Counter("sidecar.requests",
			metric.WithDescription("Requests to deployment sidecar."))
		inst.sidecarDuration, _ = m.Float64Histogram("sidecar.duration",
			metric.WithUnit("s"),
			metric.WithDescription("Sidecar request duration in seconds."))
		inst.emailSent, _ = m.Int64Counter("email.sent",
			metric.WithDescription("Emails sent by result."))
	})
	return &inst
}

func EventAppended(ctx context.Context, eventType string) {
	get().eventsAppended.Add(ctx, 1, metric.WithAttributes(attribute.String("type", eventType)))
}

func CommandHandled(ctx context.Context, command, outcome string, d time.Duration) {
	attrs := metric.WithAttributes(
		attribute.String("command", command),
		attribute.String("outcome", outcome),
	)
	get().commandHandled.Add(ctx, 1, attrs)
	get().commandDuration.Record(ctx, d.Seconds(), attrs)
}

func ProjectionError(ctx context.Context, projection string) {
	get().projectionErrors.Add(ctx, 1, metric.WithAttributes(attribute.String("projection", projection)))
}

var projectionGaugeOnce sync.Map

// ObserveProjection registers observable gauges for a projection checkpoint and lag.
// checkpoint returns the projection's last applied event ID; head returns the
// current event store head ID.
func ObserveProjection(projection string, checkpoint func(context.Context) (int64, error), head func(context.Context) (int64, error)) {
	if projection == "" || checkpoint == nil || head == nil {
		return
	}
	if _, loaded := projectionGaugeOnce.LoadOrStore(projection, true); loaded {
		return
	}
	m := otel.Meter("booking")
	attrs := metric.WithAttributes(attribute.String("projection", projection))
	_, _ = m.Int64ObservableGauge("projection.checkpoint",
		metric.WithDescription("Last applied event ID for a projection."),
		metric.WithInt64Callback(func(ctx context.Context, o metric.Int64Observer) error {
			v, err := checkpoint(ctx)
			if err != nil {
				return err
			}
			o.Observe(v, attrs)
			return nil
		}))
	_, _ = m.Int64ObservableGauge("projection.lag",
		metric.WithDescription("Event store head minus projection checkpoint."),
		metric.WithInt64Callback(func(ctx context.Context, o metric.Int64Observer) error {
			cp, err := checkpoint(ctx)
			if err != nil {
				return err
			}
			h, err := head(ctx)
			if err != nil {
				return err
			}
			lag := h - cp
			if lag < 0 {
				lag = 0
			}
			o.Observe(lag, attrs)
			return nil
		}))
}

func BookingCreated(ctx context.Context) {
	get().bookingsCreated.Add(ctx, 1)
}

func BookingCancelled(ctx context.Context) {
	get().bookingsCancelled.Add(ctx, 1)
}

func BookingRejected(ctx context.Context, reason string) {
	get().bookingsRejected.Add(ctx, 1, metric.WithAttributes(attribute.String("reason", reason)))
}

func AuthCodeIssued(ctx context.Context) {
	get().authCodesIssued.Add(ctx, 1)
}

func AuthLogin(ctx context.Context, result string) {
	get().authLogins.Add(ctx, 1, metric.WithAttributes(attribute.String("result", result)))
}

func RateLimitRejected(ctx context.Context, limiter string) {
	get().rateLimitRejected.Add(ctx, 1, metric.WithAttributes(attribute.String("limiter", limiter)))
}

func SidecarRequest(ctx context.Context, endpoint, result string, d time.Duration) {
	attrs := metric.WithAttributes(
		attribute.String("endpoint", endpoint),
		attribute.String("result", result),
	)
	get().sidecarRequests.Add(ctx, 1, attrs)
	get().sidecarDuration.Record(ctx, d.Seconds(), attrs)
}

func EmailSent(ctx context.Context, result string) {
	get().emailSent.Add(ctx, 1, metric.WithAttributes(attribute.String("result", result)))
}
