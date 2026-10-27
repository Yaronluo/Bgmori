package main

import (
	"context"
	"encoding/base64"
	"encoding/json"
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
