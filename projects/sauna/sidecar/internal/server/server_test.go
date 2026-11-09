package server_test

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/adamzki99/booking-system/projects/sauna/sidecar/internal/server"
)

func TestHealthz(t *testing.T) {
	ts := httptest.NewServer(server.NewMux())
	defer ts.Close()

	resp, err := http.Get(ts.URL + "/healthz")
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want %d", resp.StatusCode, http.StatusOK)
	}
	var body map[string]string
	if err := json.NewDecoder(resp.Body).Decode(&body); err != nil {
		t.Fatal(err)
	}
	if body["status"] != "ok" {
		t.Fatalf("status = %q, want ok", body["status"])
	}
}

func TestEchoSuccess(t *testing.T) {
	ts := httptest.NewServer(server.NewMux())
	defer ts.Close()

	resp, body := doRequest(t, ts, http.MethodPost, "/functions/echo", `{"input":"hello"}`)
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want %d (body %s)", resp.StatusCode, http.StatusOK, body)
	}
	var out struct {
		Result string `json:"result"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatal(err)
	}
	if out.Result != "hello" {
		t.Fatalf("result = %q, want hello", out.Result)
	}
}

func TestEchoBadInput(t *testing.T) {
	ts := httptest.NewServer(server.NewMux())
	defer ts.Close()

	cases := []string{
		`{not json`,
		`{}`,
		`{"input":""}`,
		`{"input": 123}`,
	}
	for _, c := range cases {
		resp, _ := doRequest(t, ts, http.MethodPost, "/functions/echo", c)
		if resp.StatusCode != http.StatusBadRequest {
			t.Fatalf("input %q: status = %d, want %d", c, resp.StatusCode, http.StatusBadRequest)
		}
	}
}

func TestChrome(t *testing.T) {
	ts := httptest.NewServer(server.NewMux())
	defer ts.Close()

	resp, body := doRequest(t, ts, http.MethodGet, "/functions/chrome", "")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want %d (body %s)", resp.StatusCode, http.StatusOK, body)
	}
	var out struct {
		Header       string `json:"header"`
		Footer       string `json:"footer"`
		NextRedeploy string `json:"nextRedeploy"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatal(err)
	}
	if out.Header == "" || out.Footer == "" {
		t.Fatalf("expected non-empty header/footer, got %+v", out)
	}
	if out.NextRedeploy != "" {
		t.Fatalf("nextRedeploy = %q, want empty when no schedule is configured", out.NextRedeploy)
	}
}

func TestChromeIncludesNextRedeploy(t *testing.T) {
	schedule := []string{"00:00", "12:00"}
	ts := httptest.NewServer(server.NewMux(server.Deps{
		Timezone:      "Europe/Stockholm",
		Capacity:      1,
		RedeployTimes: schedule,
	}))
	defer ts.Close()

	before := time.Now()
	resp, body := doRequest(t, ts, http.MethodGet, "/functions/chrome", "")
	if resp.StatusCode != http.StatusOK {
		t.Fatalf("status = %d, want %d (body %s)", resp.StatusCode, http.StatusOK, body)
	}
	var out struct {
		NextRedeploy string `json:"nextRedeploy"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatal(err)
	}
	next, err := time.Parse(time.RFC3339, out.NextRedeploy)
	if err != nil {
		t.Fatalf("parse nextRedeploy %q: %v", out.NextRedeploy, err)
	}
	if !next.After(before) {
		t.Fatalf("nextRedeploy %s is not after now %s", next, before)
	}
	if next.Sub(before) > 24*time.Hour {
		t.Fatalf("nextRedeploy %s is more than 24h away", next)
	}
}

func TestNextRedeploy(t *testing.T) {
	loc, err := time.LoadLocation("Europe/Stockholm")
	if err != nil {
		t.Fatal(err)
	}
	at := func(hour, minute int) time.Time {
		return time.Date(2026, time.November, 9, hour, minute, 0, 0, loc)
	}

	cases := []struct {
		name  string
		now   time.Time
		times []string
		want  string
	}{
		{name: "later same day", now: at(11, 0), times: []string{"00:00", "12:00"}, want: "2026-11-09T12:00:00+01:00"},
		{name: "rolls to next day", now: at(13, 0), times: []string{"00:00", "12:00"}, want: "2026-11-10T00:00:00+01:00"},
		{name: "exact time rolls over", now: at(12, 0), times: []string{"00:00", "12:00"}, want: "2026-11-10T00:00:00+01:00"},
		{name: "unset", now: at(12, 0), times: nil, want: ""},
		{name: "invalid entries ignored", now: at(12, 0), times: []string{"nope", "13:00"}, want: "2026-11-09T13:00:00+01:00"},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := server.NextRedeploy(tc.now, tc.times, loc)
			if got != tc.want {
				t.Fatalf("NextRedeploy = %q, want %q", got, tc.want)
			}
		})
	}
}

func doRequest(t *testing.T, ts *httptest.Server, method, path, body string) (*http.Response, []byte) {
	t.Helper()
	var rd io.Reader
	if body != "" {
		rd = strings.NewReader(body)
	}
	req, err := http.NewRequest(method, ts.URL+path, rd)
	if err != nil {
		t.Fatal(err)
	}
	if body != "" {
		req.Header.Set("Content-Type", "application/json")
	}
	resp, err := http.DefaultClient.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(resp.Body)
	if err != nil {
		t.Fatal(err)
	}
	return resp, data
}
