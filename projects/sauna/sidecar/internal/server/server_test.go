package server_test

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

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
		Header string `json:"header"`
		Footer string `json:"footer"`
	}
	if err := json.Unmarshal(body, &out); err != nil {
		t.Fatal(err)
	}
	if out.Header == "" || out.Footer == "" {
		t.Fatalf("expected non-empty header/footer, got %+v", out)
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
