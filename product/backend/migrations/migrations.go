// Package migrations embeds the SQL migration files.
package migrations

import "embed"

// FS contains the embedded migration SQL files.
//
//go:embed *.sql
var FS embed.FS
