package user

import "time"

const (
	// AggregateType is the user event aggregate type.
	AggregateType = "user"
	// UsersAggregateType is an alias for AggregateType.
	UsersAggregateType = "user"

	// UserCreatedEventType records a created user.
	UserCreatedEventType = "user.created"
	// UserRemovedEventType records a deactivated user.
	UserRemovedEventType = "user.removed"
	// UserEmailChangedEventType records an email change.
	UserEmailChangedEventType = "user.email_changed"
	// UserAddressChangedEventType records an address change.
	UserAddressChangedEventType = "user.address_changed"

	// Aliases.
	CreatedEventType        = "user.created"
	RemovedEventType        = "user.removed"
	EmailChangedEventType   = "user.email_changed"
	AddressChangedEventType = "user.address_changed"
)

// UserCreatedPayload is the payload for user.created events.
type UserCreatedPayload struct {
	UserID    string    `json:"user_id"`
	Email     string    `json:"email"`
	Role      Role      `json:"role"`
	Address   string    `json:"address"`
	CreatedBy string    `json:"created_by"`
	CreatedAt time.Time `json:"created_at"`
}

// UserRemovedPayload is the payload for user.removed events.
type UserRemovedPayload struct {
	UserID    string    `json:"user_id"`
	RemovedBy string    `json:"removed_by"`
	RemovedAt time.Time `json:"removed_at"`
}

// UserEmailChangedPayload is the payload for user.email_changed events.
type UserEmailChangedPayload struct {
	UserID    string    `json:"user_id"`
	OldEmail  string    `json:"old_email"`
	NewEmail  string    `json:"new_email"`
	ChangedAt time.Time `json:"changed_at"`
}

// UserAddressChangedPayload is the payload for user.address_changed events.
type UserAddressChangedPayload struct {
	UserID    string    `json:"user_id"`
	Address   string    `json:"address"`
	ChangedBy string    `json:"changed_by"`
	ChangedAt time.Time `json:"changed_at"`
}
