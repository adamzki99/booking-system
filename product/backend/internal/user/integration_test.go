package user_test

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/adamzki99/booking-system/product/backend/internal/eventstore"
	"github.com/adamzki99/booking-system/product/backend/internal/registry"
	"github.com/adamzki99/booking-system/product/backend/internal/user"
	"github.com/jackc/pgx/v5/pgxpool"
	"github.com/testcontainers/testcontainers-go"
	"github.com/testcontainers/testcontainers-go/modules/postgres"
	"github.com/testcontainers/testcontainers-go/wait"
)

const (
	superEmail = "super@example.com"
	adminEmail = "admin@example.com"
	basicEmail = "basic@example.com"
)

type userTestApp struct {
	pool    *pgxpool.Pool
	store   eventstore.Store
	app     *registry.Registry
	users   *user.UsersProjection
	service *user.UserService
}

func newUserTestApp(t *testing.T) *userTestApp {
	t.Helper()
	ctx := context.Background()
	pool := newUserTestPool(t)
	store := eventstore.NewPostgresStore(pool)
	app, err := registry.New(ctx, store, pool)
	if err != nil {
		t.Fatal(err)
	}
	users := user.Register(app)
	return &userTestApp{
		pool:    pool,
		store:   store,
		app:     app,
		users:   users,
		service: user.NewService(app.Commands, users),
	}
}

// seedUser creates a fixture user through the seed command and returns its id.
func (ta *userTestApp) seedUser(t *testing.T, email string, role user.Role) string {
	t.Helper()
	ctx := context.Background()
	if err := ta.app.Commands.Execute(ctx, user.SeedUserCommand{Email: email, Role: role}); err != nil {
		t.Fatalf("seed %s: %v", email, err)
	}
	u, err := ta.users.GetByEmail(ctx, email)
	if err != nil {
		t.Fatalf("read seeded %s: %v", email, err)
	}
	return u.ID
}

// eventsFor loads recorded events for a user aggregate.
func (ta *userTestApp) eventsFor(t *testing.T, id string) []eventstore.Event {
	t.Helper()
	events, err := ta.store.LoadByAggregate(context.Background(), user.AggregateType, id)
	if err != nil {
		t.Fatal(err)
	}
	return events
}

func TestBootstrapAdminCreatesFirstAdmin(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()

	if err := ta.service.BootstrapAdmin(ctx, "  First.Admin@Example.COM  "); err != nil {
		t.Fatal(err)
	}

	u, err := ta.users.GetByEmail(ctx, "first.admin@example.com")
	if err != nil {
		t.Fatal(err)
	}
	if u.Role != user.RoleAdmin {
		t.Fatalf("role = %q, want admin", u.Role)
	}
	if !u.Active {
		t.Fatal("bootstrap admin should be active")
	}

	events := ta.eventsFor(t, u.ID)
	if len(events) != 1 || events[0].EventType != user.UserCreatedEventType {
		t.Fatalf("expected one user.created event, got %+v", events)
	}

	// A second bootstrap is a no-op at the service layer once users exist.
	if err := ta.service.BootstrapAdmin(ctx, adminEmail); err != nil {
		t.Fatalf("second bootstrap = %v, want nil", err)
	}
	n, err := ta.users.Count(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if n != 1 {
		t.Fatalf("user count = %d, want 1", n)
	}

	// The raw command is rejected when users already exist.
	err = ta.app.Commands.Execute(ctx, user.BootstrapAdmin{Email: adminEmail})
	if !errors.Is(err, user.ErrBootstrapNotAllowed) {
		t.Fatalf("expected ErrBootstrapNotAllowed, got %v", err)
	}
}

func TestBootstrapAdminRejectsInvalidEmail(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()

	if err := ta.service.BootstrapAdmin(ctx, "not-an-email"); !errors.Is(err, user.ErrInvalidEmail) {
		t.Fatalf("expected ErrInvalidEmail, got %v", err)
	}
	n, err := ta.users.Count(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if n != 0 {
		t.Fatalf("user count = %d, want 0", n)
	}
}

func TestAddUserCreatesBasicUser(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, superEmail, user.RoleSuper)
	ta.seedUser(t, basicEmail, user.RoleBasic)

	created, err := ta.service.AddUser(ctx, " New.User@Example.com ", "  Saunatie 4 ", superEmail)
	if err != nil {
		t.Fatal(err)
	}
	if created.Email != "new.user@example.com" {
		t.Fatalf("email = %q, want normalized", created.Email)
	}
	if created.Role != user.RoleBasic {
		t.Fatalf("role = %q, want basic", created.Role)
	}
	if created.Address != "Saunatie 4" {
		t.Fatalf("address = %q, want trimmed", created.Address)
	}
	if !created.Active {
		t.Fatal("new user should be active")
	}

	events := ta.eventsFor(t, created.ID)
	if len(events) != 1 || events[0].EventType != user.UserCreatedEventType {
		t.Fatalf("expected one user.created event, got %+v", events)
	}

	// Duplicate email is rejected.
	if _, err := ta.service.AddUser(ctx, "new.user@example.com", "", superEmail); !errors.Is(err, user.ErrDuplicateEmail) {
		t.Fatalf("expected ErrDuplicateEmail, got %v", err)
	}

	// A basic requester is not allowed to add users.
	if _, err := ta.service.AddUser(ctx, "other@example.com", "", basicEmail); !errors.Is(err, user.ErrForbidden) {
		t.Fatalf("expected ErrForbidden for basic requester, got %v", err)
	}

	// An unknown requester is not allowed to add users.
	if _, err := ta.service.AddUser(ctx, "other@example.com", "", "ghost@example.com"); !errors.Is(err, user.ErrForbidden) {
		t.Fatalf("expected ErrForbidden for unknown requester, got %v", err)
	}
}

func TestAddUserAdminRequesterAllowed(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, adminEmail, user.RoleAdmin)

	if _, err := ta.service.AddUser(ctx, basicEmail, "", adminEmail); err != nil {
		t.Fatalf("admin add user = %v, want nil", err)
	}
}

func TestRemoveUserDeactivatesBasicUser(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, superEmail, user.RoleSuper)
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)

	if err := ta.service.RemoveUser(ctx, basicID, superEmail); err != nil {
		t.Fatal(err)
	}

	got, err := ta.users.GetByID(ctx, basicID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Active {
		t.Fatal("removed user should be inactive")
	}
	if got.DeactivatedAt == nil {
		t.Fatal("removed user should have a deactivation timestamp")
	}

	events := ta.eventsFor(t, basicID)
	if len(events) != 2 || events[1].EventType != user.UserRemovedEventType {
		t.Fatalf("expected user.created followed by user.removed, got %+v", events)
	}

	// Removing an already removed user fails.
	if err := ta.service.RemoveUser(ctx, basicID, superEmail); !errors.Is(err, user.ErrNotRemovable) {
		t.Fatalf("expected ErrNotRemovable, got %v", err)
	}
}

func TestRemoveUserAuthorization(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	superID := ta.seedUser(t, superEmail, user.RoleSuper)
	adminID := ta.seedUser(t, adminEmail, user.RoleAdmin)
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)

	// A basic requester cannot remove anyone, not even themselves.
	if err := ta.service.RemoveUser(ctx, basicID, basicEmail); !errors.Is(err, user.ErrForbidden) {
		t.Fatalf("expected ErrForbidden for basic self removal, got %v", err)
	}
	if err := ta.service.RemoveUser(ctx, adminID, basicEmail); !errors.Is(err, user.ErrForbidden) {
		t.Fatalf("expected ErrForbidden for basic requester, got %v", err)
	}

	// A super requester may not remove a self and may not remove non-basic users.
	if err := ta.service.RemoveUser(ctx, superID, superEmail); !errors.Is(err, user.ErrSelfRemoval) {
		t.Fatalf("expected ErrSelfRemoval, got %v", err)
	}
	if err := ta.service.RemoveUser(ctx, adminID, superEmail); !errors.Is(err, user.ErrTargetNotBasic) {
		t.Fatalf("expected ErrTargetNotBasic, got %v", err)
	}

	// An admin requester cannot remove another admin.
	admin2ID := ta.seedUser(t, "admin2@example.com", user.RoleAdmin)
	if err := ta.service.RemoveUser(ctx, admin2ID, adminEmail); !errors.Is(err, user.ErrNotRemovable) {
		t.Fatalf("expected ErrNotRemovable, got %v", err)
	}

	// Unknown target.
	if err := ta.service.RemoveUser(ctx, "00000000-0000-0000-0000-0000000000ff", adminEmail); !errors.Is(err, user.ErrUserNotFound) {
		t.Fatalf("expected ErrUserNotFound, got %v", err)
	}

	// Nothing above should have deactivated anybody.
	for _, id := range []string{superID, adminID, basicID} {
		u, err := ta.users.GetByID(ctx, id)
		if err != nil {
			t.Fatal(err)
		}
		if !u.Active {
			t.Fatalf("user %s should still be active", u.Email)
		}
	}
}

func TestChangeUserAddressUpdatesProjection(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, superEmail, user.RoleSuper)
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)

	updated, err := ta.service.ChangeUserAddress(ctx, basicID, "  New Address 12 ", superEmail)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Address != "New Address 12" {
		t.Fatalf("address = %q, want trimmed", updated.Address)
	}

	events := ta.eventsFor(t, basicID)
	var found bool
	for _, e := range events {
		if e.EventType == user.UserAddressChangedEventType {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected user.address_changed event, got %+v", events)
	}
}

func TestChangeUserAddressAuthorization(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, superEmail, user.RoleSuper)
	admin2ID := ta.seedUser(t, "admin2@example.com", user.RoleAdmin)
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)

	// Basic requester is forbidden.
	if _, err := ta.service.ChangeUserAddress(ctx, basicID, "Elsewhere 1", basicEmail); !errors.Is(err, user.ErrForbidden) {
		t.Fatalf("expected ErrForbidden, got %v", err)
	}

	// Only basic targets may have their address changed.
	if _, err := ta.service.ChangeUserAddress(ctx, admin2ID, "Elsewhere 1", superEmail); !errors.Is(err, user.ErrTargetNotBasic) {
		t.Fatalf("expected ErrTargetNotBasic, got %v", err)
	}

	// Unknown target.
	if _, err := ta.service.ChangeUserAddress(ctx, "00000000-0000-0000-0000-0000000000ff", "Elsewhere 1", superEmail); !errors.Is(err, user.ErrUserNotFound) {
		t.Fatalf("expected ErrUserNotFound, got %v", err)
	}

	got, err := ta.users.GetByID(ctx, basicID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Address != "" {
		t.Fatalf("address = %q, want unchanged", got.Address)
	}
}

func TestChangeUserRoleRequiresAdmin(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, superEmail, user.RoleSuper)
	ta.seedUser(t, adminEmail, user.RoleAdmin)
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)

	if _, err := ta.service.ChangeUserRole(ctx, basicID, user.RoleSuper, basicEmail); !errors.Is(err, user.ErrForbidden) {
		t.Fatalf("expected ErrForbidden for basic requester, got %v", err)
	}
	if _, err := ta.service.ChangeUserRole(ctx, basicID, user.RoleSuper, superEmail); !errors.Is(err, user.ErrForbidden) {
		t.Fatalf("expected ErrForbidden for super requester, got %v", err)
	}

	got, err := ta.users.GetByID(ctx, basicID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Role != user.RoleBasic {
		t.Fatalf("role = %q, want unchanged basic", got.Role)
	}
}

func TestChangeUserRoleUpdatesProjectionAndEvent(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, adminEmail, user.RoleAdmin)
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)

	updated, err := ta.service.ChangeUserRole(ctx, basicID, user.RoleSuper, adminEmail)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Role != user.RoleSuper {
		t.Fatalf("role = %q, want super", updated.Role)
	}

	events := ta.eventsFor(t, basicID)
	var roleEvent *eventstore.Event
	for i := range events {
		if events[i].EventType == user.UserRoleChangedEventType {
			roleEvent = &events[i]
		}
	}
	if roleEvent == nil {
		t.Fatalf("expected user.role_changed event, got %+v", events)
	}
}

func TestChangeUserRoleRejectsInvalidRole(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, adminEmail, user.RoleAdmin)
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)

	if _, err := ta.service.ChangeUserRole(ctx, basicID, "wizard", adminEmail); !errors.Is(err, user.ErrInvalidRole) {
		t.Fatalf("expected ErrInvalidRole, got %v", err)
	}
}

// TestChangeUserRoleFallsBackToNewRoleField pins the current handler behavior:
// a blank Role falls back to NewRole.
func TestChangeUserRoleFallsBackToNewRoleField(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, adminEmail, user.RoleAdmin)
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)

	err := ta.app.Commands.Execute(ctx, user.ChangeUserRole{
		UserID:         basicID,
		NewRole:        user.RoleSuper,
		RequesterEmail: adminEmail,
	})
	if err != nil {
		t.Fatal(err)
	}

	got, err := ta.users.GetByID(ctx, basicID)
	if err != nil {
		t.Fatal(err)
	}
	if got.Role != user.RoleSuper {
		t.Fatalf("role = %q, want super", got.Role)
	}
}

func TestChangeOwnEmail(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)

	updated, err := ta.service.ChangeOwnEmail(ctx, basicID, "Renamed@Example.com", basicEmail)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Email != "renamed@example.com" {
		t.Fatalf("email = %q, want normalized new email", updated.Email)
	}

	events := ta.eventsFor(t, basicID)
	var found bool
	for _, e := range events {
		if e.EventType == user.UserEmailChangedEventType {
			found = true
		}
	}
	if !found {
		t.Fatalf("expected user.email_changed event, got %+v", events)
	}
}

func TestChangeOwnEmailAuthorizationAndConflicts(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, adminEmail, user.RoleAdmin)
	basicID := ta.seedUser(t, basicEmail, user.RoleBasic)
	otherID := ta.seedUser(t, "other@example.com", user.RoleBasic)

	// Unrelated basic user cannot change someone else's email.
	if _, err := ta.service.ChangeOwnEmail(ctx, basicID, "hijack@example.com", "other@example.com"); !errors.Is(err, user.ErrForbidden) {
		t.Fatalf("expected ErrForbidden, got %v", err)
	}

	// Duplicate email is rejected.
	if _, err := ta.service.ChangeOwnEmail(ctx, otherID, basicEmail, adminEmail); !errors.Is(err, user.ErrDuplicateEmail) {
		t.Fatalf("expected ErrDuplicateEmail, got %v", err)
	}

	// An admin may change another user's email.
	updated, err := ta.service.ChangeOwnEmail(ctx, otherID, "moved@example.com", adminEmail)
	if err != nil {
		t.Fatal(err)
	}
	if updated.Email != "moved@example.com" {
		t.Fatalf("email = %q, want moved@example.com", updated.Email)
	}

	// Unknown target user.
	if _, err := ta.service.ChangeOwnEmail(ctx, "00000000-0000-0000-0000-0000000000ff", "x@example.com", adminEmail); !errors.Is(err, user.ErrUserNotFound) {
		t.Fatalf("expected ErrUserNotFound, got %v", err)
	}
}

func TestServiceRoleOfAndListUsers(t *testing.T) {
	ta := newUserTestApp(t)
	ctx := context.Background()
	ta.seedUser(t, superEmail, user.RoleSuper)
	ta.seedUser(t, basicEmail, user.RoleBasic)

	role, ok := ta.service.RoleOf(ctx, superEmail)
	if !ok || role != user.RoleSuper {
		t.Fatalf("RoleOf(%q) = %q,%v", superEmail, role, ok)
	}
	if _, ok := ta.service.RoleOf(ctx, "missing@example.com"); ok {
		t.Fatal("RoleOf for missing user should return false")
	}

	list, err := ta.service.ListUsers(ctx)
	if err != nil {
		t.Fatal(err)
	}
	if len(list) != 2 {
		t.Fatalf("ListUsers returned %d users, want 2", len(list))
	}
}

func newUserTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	ctx := context.Background()

	if url := os.Getenv("DATABASE_URL"); url != "" {
		pool, err := pgxpool.New(ctx, url)
		if err != nil {
			t.Fatal(err)
		}
		t.Cleanup(pool.Close)
		return pool
	}

	container, err := postgres.Run(ctx, "postgres:16",
		postgres.WithDatabase("test"),
		postgres.WithUsername("test"),
		postgres.WithPassword("test"),
		testcontainers.WithWaitStrategy(wait.ForLog("database system is ready to accept connections").WithOccurrence(2)),
	)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = container.Terminate(ctx) })

	url, err := container.ConnectionString(ctx, "sslmode=disable")
	if err != nil {
		t.Fatal(err)
	}
	pool, err := pgxpool.New(ctx, url)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(pool.Close)
	return pool
}
