package main

import (
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"testing"
)

func TestConfigParsing(t *testing.T) {
	config := []byte{0, 4, 1, 2, 3, 4}
	encoded := base64.StdEncoding.EncodeToString(config)
	body, _ := json.Marshal(map[string]any{"Answer": []map[string]any{{"data": "1 . ech=\"" + encoded + "\""}}})
	if string(parseConfig(body)) != string(config) {
		t.Fatal("Quoted ECH parameter did not survive DNS JSON parsing")
	}
	for _, bad := range []string{`{}`, `{"Answer":[{"data":"1 . alpn=h2"}]}`, `{"Answer":[{"data":"ech=broken"}]}`} {
		if parseConfig([]byte(bad)) != nil {
			t.Fatal("Invalid ECH configuration was accepted")
		}
	}
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (fn roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return fn(r) }

func TestIsolatedLoginCookies(t *testing.T) {
	transport := echHTTP.Transport
	defer func() { echHTTP.Transport = transport }()
	var sentCookie string
	echHTTP.Transport = roundTripFunc(func(req *http.Request) (*http.Response, error) {
		sentCookie = req.Header.Get("Cookie")
		return &http.Response{StatusCode: 200, Header: http.Header{"Set-Cookie": []string{"session=fixture; Secure; Path=/"}},
			Body: io.NopCloser(strings.NewReader("ok")), TLS: &tls.ConnectionState{ECHAccepted: true}}, nil
	})
	request := input{URL: "https://bgm.tv/login", Method: "GET", Headers: map[string]string{"Cookie": "session=fixture"}}
	result := perform(context.Background(), request)
	if sentCookie != "" || len(result.Cookies) != 0 || result.Headers["Set-Cookie"] != "" {
		t.Fatal("Anonymous transport exposed website cookies")
	}
	request.WebLogin = true
	result = perform(context.Background(), request)
	if sentCookie == "" || len(result.Cookies) != 1 || !result.ECHAccepted {
		t.Fatal("Isolated login session failed to exchange cookies")
	}
	request.URL = "https://bgm.tv/group/test/new_topic"
	if perform(context.Background(), request).Error != "UNSUPPORTED_HOST" {
		t.Fatal("Login cookies escaped the authentication endpoint boundary")
	}
	redirect, _ := http.NewRequestWithContext(context.WithValue(context.Background(), loginContextKey{}, true), "GET", "https://bgm.tv/login", nil)
	if echHTTP.CheckRedirect(redirect, nil) != http.ErrUseLastResponse {
		t.Fatal("Login redirects must never be followed")
	}
}
func TestRequestBoundary(t *testing.T) {
	for _, target := range []string{"http://bgm.tv/", "https://evil.test/", "https://bgm.tv.evil.test/", "https://user@bgm.tv/", "https://bgm.tv:444/"} {
		result := perform(context.Background(), input{URL: target, Method: "GET"})
		if result.Error != "UNSUPPORTED_HOST" || result.ECHAccepted {
			t.Fatal("Untrusted destination crossed the ECH boundary")
		}
	}
	result := perform(context.Background(), input{URL: "https://bgm.tv/", Method: "CONNECT"})
	if result.Error != "UNSUPPORTED_METHOD" {
		t.Fatal("Unsupported method was not rejected")
	}
}
func TestDirectInterfaces(t *testing.T) {
	for _, iface := range physicalInterfaces() {
		if !strings.HasPrefix(iface.Name, "en") && !strings.HasPrefix(iface.Name, "pdp_ip") {
			t.Fatal("A VPN interface was selected")
		}
	}
	if echHTTP.Transport.(*http.Transport).Proxy != nil {
		t.Fatal("ECH must not inherit a proxy")
	}
}

func TestCancelledRequestDoesNotBootstrap(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	result := perform(ctx, input{URL: "https://api.bgm.tv/v0/subjects/8", Method: "GET"})
	if result.Error != "CANCELLED" || result.ECHAccepted {
		t.Fatal("Cancelled request was not rejected before network setup")
	}
}
