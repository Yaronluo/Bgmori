// Bgmori's ECH-only HTTP transport. It never logs requests, headers or bodies.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"bytes"
	"context"
	"crypto/tls"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"regexp"
	"runtime"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
	"unsafe"
)

var allowedHosts = map[string]bool{"bgm.tv": true, "api.bgm.tv": true, "lain.bgm.tv": true, "next.bgm.tv": true, "doujin.bgm.tv": true}

// Cloudflare IPv4 entry points maintained in this project. ECH configuration
// is refreshed through HTTPS DNS only; no external address list is fetched.
var bundledAddresses = []string{"172.67.134.140", "104.21.6.61", "172.67.73.67", "104.26.8.23"}
var dohEndpoints = []string{
	"https://dns.alidns.com/resolve?name=crypto.cloudflare.com&type=65",
	"https://doh.360.cn/resolve?name=crypto.cloudflare.com&type=65",
	"https://cloudflare-dns.com/dns-query?name=crypto.cloudflare.com&type=HTTPS",
}
var echPattern = regexp.MustCompile(`ech="?([A-Za-z0-9+/]+=*)`)
var directBootstrap = &http.Client{Timeout: 3 * time.Second, Transport: &http.Transport{Proxy: nil, DialContext: bootstrapDial, MaxIdleConns: 4, IdleConnTimeout: 30 * time.Second}, CheckRedirect: func(r *http.Request, via []*http.Request) error {
	if r.URL.Scheme != "https" || len(via) > 3 {
		return http.ErrUseLastResponse
	}
	return nil
}}

type configState struct {
	sync.Mutex
	config        []byte
	fetched       time.Time
	rejected      []byte
	loading       chan struct{}
	addresses     []string
	learned       map[string]string
	interfaceName string
}

var state = configState{addresses: bundledAddresses, learned: map[string]string{}}
var accepted atomic.Uint64

// Bind only this transport's sockets to a physical interface. This prevents a
// system packet-tunnel route from turning an ECH probe into a VPN success.
func physicalInterfaces() []net.Interface {
	all, _ := net.Interfaces()
	var result []net.Interface
	for _, prefix := range []string{"en", "pdp_ip"} {
		for _, iface := range all {
			if !strings.HasPrefix(iface.Name, prefix) || iface.Flags&net.FlagUp == 0 {
				continue
			}
			addresses, _ := iface.Addrs()
			hasIPv4 := false
			for _, raw := range addresses {
				ip, _, _ := net.ParseCIDR(raw.String())
				if ip != nil && ip.To4() != nil && !ip.IsLoopback() {
					hasIPv4 = true
				}
			}
			if hasIPv4 {
				result = append(result, iface)
			}
		}
	}
	return result
}

func boundDialer(iface net.Interface) *net.Dialer {
	return &net.Dialer{Timeout: 3 * time.Second, Control: func(network, address string, connection syscall.RawConn) error {
		var boundErr error
		err := connection.Control(func(fd uintptr) {
			boundErr = syscall.SetsockoptInt(int(fd), syscall.IPPROTO_IP, syscall.IP_BOUND_IF, iface.Index)
		})
		if err != nil {
			return err
		}
		return boundErr
	}}
}

func bootstrapDial(ctx context.Context, network, address string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil {
		return nil, err
	}
	// Literal resolver addresses avoid a VPN's synthetic DNS answers as well.
	targets := []string{host}
	switch host {
	case "dns.alidns.com":
		targets = []string{"223.5.5.5", "223.6.6.6"}
	case "cloudflare-dns.com":
		targets = []string{"1.1.1.1", "1.0.0.1"}
	}
	var last error = errors.New("NO_DIRECT_INTERFACE")
	for _, iface := range physicalInterfaces() {
		for _, target := range targets {
			conn, err := boundDialer(iface).DialContext(ctx, "tcp4", net.JoinHostPort(target, port))
			if err == nil {
				return conn, nil
			}
			last = err
			if ctx.Err() != nil {
				return nil, ctx.Err()
			}
		}
	}
	return nil, last
}

func readHTTPS(ctx context.Context, endpoint string, limit int64) ([]byte, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, endpoint, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "Bgmori/1.0 (ECH configuration)")
	req.Header.Set("Accept", "application/dns-json,application/json")
	resp, err := directBootstrap.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 200 {
		return nil, errors.New("bootstrap HTTP failure")
	}
	return io.ReadAll(io.LimitReader(resp.Body, limit))
}

func parseConfig(body []byte) []byte {
	var message struct {
		Answer []struct {
			Data string `json:"data"`
		} `json:"Answer"`
	}
	if json.Unmarshal(body, &message) != nil {
		return nil
	}
	for _, answer := range message.Answer {
		match := echPattern.FindStringSubmatch(answer.Data)
		if len(match) > 1 {
			config, err := base64.StdEncoding.DecodeString(match[1])
			if err == nil && len(config) > 4 && len(config) <= 65535 {
				return config
			}
		}
	}
	return nil
}

func refreshConfig() {
	ctx, cancel := context.WithTimeout(context.Background(), 8*time.Second)
	defer cancel()
	var result []byte
	for _, endpoint := range dohEndpoints {
		body, err := readHTTPS(ctx, endpoint, 128<<10)
		if err != nil {
			continue
		}
		candidate := parseConfig(body)
		state.Lock()
		rejected := bytes.Equal(candidate, state.rejected)
		state.Unlock()
		if len(candidate) > 0 && !rejected {
			result = candidate
			break
		}
	}
	state.Lock()
	if len(result) > 0 {
		state.config = result
		state.fetched = time.Now()
		state.rejected = nil
	}
	close(state.loading)
	state.loading = nil
	state.Unlock()
}

func getConfig(ctx context.Context) ([]byte, error) {
	for {
		state.Lock()
		if len(state.config) > 0 && time.Since(state.fetched) < 2*time.Hour {
			result := append([]byte(nil), state.config...)
			state.Unlock()
			return result, nil
		}
		if state.loading == nil {
			state.loading = make(chan struct{})
			go refreshConfig()
		}
		ready := state.loading
		state.Unlock()
		select {
		case <-ctx.Done():
			return nil, ctx.Err()
		case <-ready:
			state.Lock()
			valid := len(state.config) > 0 && time.Since(state.fetched) < 2*time.Hour
			state.Unlock()
			if !valid {
				return nil, errors.New("ECH_CONFIG_UNAVAILABLE")
			}
		}
	}
}

func addresses(host string) []string {
	state.Lock()
	defer state.Unlock()
	result := append([]string(nil), state.addresses...)
	if learned := state.learned[host]; learned != "" {
		result = append([]string{learned}, result...)
	}
	seen := map[string]bool{}
	unique := result[:0]
	for _, ip := range result {
		if !seen[ip] {
			unique = append(unique, ip)
			seen[ip] = true
		}
	}
	return unique
}

func dialECH(ctx context.Context, network, address string) (net.Conn, error) {
	host, port, err := net.SplitHostPort(address)
	if err != nil || port != "443" || !allowedHosts[host] {
		return nil, errors.New("UNSUPPORTED_HOST")
	}
	config, err := getConfig(ctx)
	if err != nil {
		return nil, err
	}
	var last error
	for _, iface := range physicalInterfaces() {
		for _, ip := range addresses(host) {
			for attempt := 0; attempt < 2; attempt++ {
				dialCtx, cancel := context.WithTimeout(ctx, 4*time.Second)
				dialer := tls.Dialer{NetDialer: boundDialer(iface), Config: &tls.Config{
					ServerName: host, MinVersion: tls.VersionTLS13, EncryptedClientHelloConfigList: config,
					NextProtos: []string{"http/1.1"},
				}}
				conn, err := dialer.DialContext(dialCtx, "tcp", net.JoinHostPort(ip, "443"))
				cancel()
				if err == nil {
					if !conn.(*tls.Conn).ConnectionState().ECHAccepted {
						conn.Close()
						return nil, errors.New("ECH_NOT_ACCEPTED")
					}
					accepted.Add(1)
					state.Lock()
					state.learned[host] = ip
					state.interfaceName = iface.Name
					state.Unlock()
					return conn, nil
				}
				last = err
				var rejected *tls.ECHRejectionError
				if attempt == 0 && errors.As(err, &rejected) {
					if len(rejected.RetryConfigList) > 0 {
						// Go verifies the ECH provider's certificate before exposing retry configs.
						config = append([]byte(nil), rejected.RetryConfigList...)
						state.Lock()
						state.config = config
						state.fetched = time.Now()
						state.rejected = nil
						state.Unlock()
						continue
					}
					state.Lock()
					state.rejected = config
					state.config = nil
					state.Unlock()
					if replacement, refreshErr := getConfig(ctx); refreshErr == nil {
						config = replacement
						continue
					}
				}
				break
			}
			if ctx.Err() != nil {
				return nil, ctx.Err()
			}
		}
	}
	if last == nil {
		last = errors.New("NO_DIRECT_INTERFACE")
	}
	return nil, last
}

var echHTTP = &http.Client{
	Transport: &http.Transport{Proxy: nil, DialTLSContext: dialECH, ForceAttemptHTTP2: false, MaxIdleConns: 24,
		MaxIdleConnsPerHost: 4, MaxConnsPerHost: 4, IdleConnTimeout: 60 * time.Second, ResponseHeaderTimeout: 12 * time.Second},
	CheckRedirect: func(request *http.Request, previous []*http.Request) error {
		if request.Context().Value(loginContextKey{}) == true {
			return http.ErrUseLastResponse
		}
		if len(previous) >= 5 || request.URL.Scheme != "https" || request.URL.User != nil ||
			request.URL.Port() != "" && request.URL.Port() != "443" || !allowedHosts[request.URL.Hostname()] {
			return http.ErrUseLastResponse
		}
		first := previous[0]
		if first.Method != "GET" && first.Method != "HEAD" {
			return http.ErrUseLastResponse
		}
		if first.Header.Get("Authorization") != "" && request.URL.Hostname() != first.URL.Hostname() {
			return http.ErrUseLastResponse
		}
		return nil
	},
}

type input struct {
	URL                 string            `json:"url"`
	Method              string            `json:"method"`
	Headers             map[string]string `json:"headers"`
	Body                []byte            `json:"body"`
	TimeoutMilliseconds int               `json:"timeoutMilliseconds"`
	WebLogin            bool              `json:"webLogin"`
}
type loginContextKey struct{}

func loginEndpoint(target *url.URL, method string) bool {
	switch target.Hostname() {
	case "bgm.tv":
		return method == "GET" && (target.Path == "/login" || target.Path == "/signup/captcha") || method == "POST" && target.Path == "/FollowTheRabbit"
	case "next.bgm.tv":
		return method == "GET" && target.Path == "/demo/access-token" || (method == "POST" || method == "DELETE") && target.Path == "/demo/access-tokens"
	case "api.bgm.tv":
		return method == "GET" && target.Path == "/v0/me"
	}
	return false
}

type output struct {
	Status      int               `json:"status"`
	Headers     map[string]string `json:"headers,omitempty"`
	Body        []byte            `json:"body,omitempty"`
	ECHAccepted bool              `json:"echAccepted"`
	Error       string            `json:"error,omitempty"`
	Cookies     []string          `json:"cookies,omitempty"`
}
type requestContext struct {
	ctx    context.Context
	cancel context.CancelFunc
}

var active = struct {
	sync.Mutex
	items map[string]requestContext
}{items: map[string]requestContext{}}

//export BgmoriECHBegin
func BgmoriECHBegin(raw *C.char) {
	id := C.GoString(raw)
	ctx, cancel := context.WithCancel(context.Background())
	active.Lock()
	active.items[id] = requestContext{ctx, cancel}
	active.Unlock()
}

//export BgmoriECHCancel
func BgmoriECHCancel(raw *C.char) {
	active.Lock()
	entry, ok := active.items[C.GoString(raw)]
	active.Unlock()
	if ok {
		entry.cancel()
	}
}

func perform(ctx context.Context, request input) output {
	if ctx.Err() != nil {
		return output{Error: "CANCELLED"}
	}
	target, err := url.Parse(request.URL)
	if err != nil || target.Scheme != "https" || !allowedHosts[target.Hostname()] || target.User != nil || target.Port() != "" && target.Port() != "443" {
		return output{Error: "UNSUPPORTED_HOST"}
	}
	switch request.Method {
	case "GET", "HEAD", "POST", "PUT", "PATCH", "DELETE":
	default:
		return output{Error: "UNSUPPORTED_METHOD"}
	}
	if request.WebLogin {
		if !loginEndpoint(target, request.Method) {
			return output{Error: "UNSUPPORTED_HOST"}
		}
		ctx = context.WithValue(ctx, loginContextKey{}, true)
	}
	timeout := time.Duration(request.TimeoutMilliseconds) * time.Millisecond
	if timeout <= 0 || timeout > 60*time.Second {
		timeout = 30 * time.Second
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()
	req, err := http.NewRequestWithContext(ctx, request.Method, request.URL, bytes.NewReader(request.Body))
	if err != nil {
		return output{Error: "INVALID_REQUEST"}
	}
	for name, value := range request.Headers {
		if strings.EqualFold(name, "Host") || strings.EqualFold(name, "Cookie") && !request.WebLogin || strings.EqualFold(name, "Proxy-Authorization") {
			continue
		}
		req.Header.Set(name, value)
	}
	resp, err := echHTTP.Do(req)
	if err != nil {
		if errors.Is(ctx.Err(), context.Canceled) {
			return output{Error: "CANCELLED"}
		}
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return output{Error: "TIMEOUT"}
		}
		var rejected *tls.ECHRejectionError
		if errors.As(err, &rejected) {
			return output{Error: "ECH_REJECTED"}
		}
		return output{Error: "ECH_CONNECTION_FAILED"}
	}
	defer resp.Body.Close()
	if resp.TLS == nil || !resp.TLS.ECHAccepted {
		return output{Error: "ECH_NOT_ACCEPTED"}
	}
	body, err := io.ReadAll(io.LimitReader(resp.Body, (32<<20)+1))
	if err != nil {
		if errors.Is(ctx.Err(), context.Canceled) {
			return output{Error: "CANCELLED"}
		}
		if errors.Is(ctx.Err(), context.DeadlineExceeded) {
			return output{Error: "TIMEOUT"}
		}
		return output{Error: "READ_FAILED"}
	}
	if len(body) > 32<<20 {
		return output{Error: "RESPONSE_TOO_LARGE"}
	}
	headers := map[string]string{}
	for name, values := range resp.Header {
		if !strings.EqualFold(name, "Set-Cookie") {
			headers[name] = strings.Join(values, ", ")
		}
	}
	result := output{Status: resp.StatusCode, Headers: headers, Body: body, ECHAccepted: true}
	if request.WebLogin {
		result.Cookies = resp.Header.Values("Set-Cookie")
	}
	return result
}

//export BgmoriECHPerform
func BgmoriECHPerform(identifier, raw *C.char) *C.char {
	id := C.GoString(identifier)
	active.Lock()
	entry, ok := active.items[id]
	active.Unlock()
	if !ok {
		return C.CString(`{"error":"CANCELLED","echAccepted":false,"status":0}`)
	}
	defer func() { entry.cancel(); active.Lock(); delete(active.items, id); active.Unlock() }()
	var request input
	if json.Unmarshal([]byte(C.GoString(raw)), &request) != nil {
		return C.CString(`{"error":"INVALID_REQUEST","echAccepted":false,"status":0}`)
	}
	result := perform(entry.ctx, request)
	encoded, _ := json.Marshal(result)
	return C.CString(string(encoded))
}

//export BgmoriECHFree
func BgmoriECHFree(pointer *C.char) { C.free(unsafe.Pointer(pointer)) }

//export BgmoriECHInfo
func BgmoriECHInfo() *C.char {
	state.Lock()
	ready := len(state.config) > 0
	age := int64(-1)
	if ready {
		age = int64(time.Since(state.fetched).Seconds())
	}
	iface := state.interfaceName
	state.Unlock()
	active.Lock()
	activeCount := len(active.items)
	active.Unlock()
	encoded, _ := json.Marshal(map[string]any{"runtime": runtime.Version(), "configReady": ready, "configAgeSeconds": age, "acceptedConnections": accepted.Load(), "proxyDisabled": true, "directInterface": iface, "activeRequests": activeCount})
	return C.CString(string(encoded))
}

func main() {}
