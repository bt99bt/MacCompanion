package main

import (
	"bytes"
	"encoding/binary"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"regexp"
	"strconv"
	"strings"
	"sync"
	"time"
)

type codeStore struct {
	mu   sync.RWMutex
	code string
}

func (s *codeStore) set(code string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	s.code = code
}

func (s *codeStore) get() string {
	s.mu.RLock()
	defer s.mu.RUnlock()
	return s.code
}

type appConfig struct {
	HTTPAddr        string
	DNSAddr         string
	CodeDomain      string
	HealthDomain    string
	HealthAddress   string
	EmptyAddress    string
	DefaultDNSReply  string
	DNSTTLSeconds    uint32
	MaxDNSPacketSize int
}

type dnsQuestion struct {
	Name   string
	RawEnd int
	QType  uint16
	QClass uint16
}

var codePattern = regexp.MustCompile(`^\d{6}$`)

func main() {
	config := loadConfig()
	store := &codeStore{}

	go serveDNSUDP(config, store)
	go serveDNSTCP(config, store)

	mux := http.NewServeMux()
	mux.HandleFunc("/push", pushHandler(store))
	mux.HandleFunc("/push/", pushPathHandler(store))
	mux.HandleFunc("/code", codeHandler(store, config))
	mux.HandleFunc("/health", healthHandler(config))

	httpServer := &http.Server{
		Addr:              config.HTTPAddr,
		Handler:           mux,
		ReadHeaderTimeout: 5 * time.Second,
	}
	log.Printf("http listening on %s", config.HTTPAddr)
	if err := httpServer.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatalf("http failed: %v", err)
	}
}

func loadConfig() appConfig {
	baseDomain := cleanDomain(env("BASE_DOMAIN", "wifi-code.example.com"))
	return appConfig{
		HTTPAddr:        env("HTTP_ADDR", ":8080"),
		DNSAddr:         env("DNS_ADDR", ":53"),
		CodeDomain:      cleanDomain(env("CODE_DOMAIN", "code."+baseDomain)),
		HealthDomain:    cleanDomain(env("HEALTH_DOMAIN", "health."+baseDomain)),
		HealthAddress:   env("HEALTH_ADDRESS", "1.255.255.255"),
		EmptyAddress:    env("EMPTY_ADDRESS", "0.0.0.0"),
		DefaultDNSReply:  env("DEFAULT_DNS_REPLY", "0.0.0.0"),
		DNSTTLSeconds:    5,
		MaxDNSPacketSize: 512,
	}
}

func pushHandler(store *codeStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"ok": false, "message": "method not allowed"})
			return
		}
		acceptCode(w, store, r.URL.Query().Get("code"))
	}
}

func pushPathHandler(store *codeStore) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, map[string]any{"ok": false, "message": "method not allowed"})
			return
		}
		acceptCode(w, store, strings.TrimPrefix(r.URL.Path, "/push/"))
	}
}

func acceptCode(w http.ResponseWriter, store *codeStore, code string) {
	code = normalizeCode(code)
	if !codePattern.MatchString(code) {
		writeJSON(w, http.StatusBadRequest, map[string]any{"ok": false, "message": "code must be 6 digits"})
		return
	}
	store.set(code)
	log.Printf("updated code: %s", code)
	writeJSON(w, http.StatusOK, map[string]any{"ok": true, "code": code})
}

func codeHandler(store *codeStore, config appConfig) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":      true,
			"code":    store.get(),
			"address": codeToAddressOrEmpty(store.get(), config.EmptyAddress),
		})
	}
}

func healthHandler(config appConfig) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		writeJSON(w, http.StatusOK, map[string]any{
			"ok":            true,
			"codeDomain":    config.CodeDomain,
			"healthDomain":  config.HealthDomain,
			"healthAddress": config.HealthAddress,
		})
	}
}

func serveDNSUDP(config appConfig, store *codeStore) {
	conn, err := net.ListenPacket("udp", config.DNSAddr)
	if err != nil {
		log.Fatalf("dns udp failed: %v", err)
	}
	defer conn.Close()
	log.Printf("dns udp listening on %s", config.DNSAddr)

	buffer := make([]byte, config.MaxDNSPacketSize)
	for {
		n, addr, err := conn.ReadFrom(buffer)
		if err != nil {
			log.Printf("dns udp read failed: %v", err)
			continue
		}
		query := append([]byte(nil), buffer[:n]...)
		go func() {
			response := buildDNSResponse(query, config, store)
			if len(response) == 0 {
				return
			}
			if _, err := conn.WriteTo(response, addr); err != nil {
				log.Printf("dns udp write failed: %v", err)
			}
		}()
	}
}

func serveDNSTCP(config appConfig, store *codeStore) {
	listener, err := net.Listen("tcp", config.DNSAddr)
	if err != nil {
		log.Fatalf("dns tcp failed: %v", err)
	}
	defer listener.Close()
	log.Printf("dns tcp listening on %s", config.DNSAddr)

	for {
		conn, err := listener.Accept()
		if err != nil {
			log.Printf("dns tcp accept failed: %v", err)
			continue
		}
		go handleDNSTCPConn(conn, config, store)
	}
}

func handleDNSTCPConn(conn net.Conn, config appConfig, store *codeStore) {
	defer conn.Close()
	if err := conn.SetDeadline(time.Now().Add(5 * time.Second)); err != nil {
		log.Printf("dns tcp deadline failed: %v", err)
	}

	var lengthBytes [2]byte
	if _, err := io.ReadFull(conn, lengthBytes[:]); err != nil {
		return
	}
	length := int(binary.BigEndian.Uint16(lengthBytes[:]))
	if length <= 0 || length > 4096 {
		return
	}
	query := make([]byte, length)
	if _, err := io.ReadFull(conn, query); err != nil {
		return
	}

	response := buildDNSResponse(query, config, store)
	if len(response) == 0 || len(response) > 65535 {
		return
	}
	var prefix [2]byte
	binary.BigEndian.PutUint16(prefix[:], uint16(len(response)))
	if _, err := conn.Write(append(prefix[:], response...)); err != nil {
		log.Printf("dns tcp write failed: %v", err)
	}
}

func buildDNSResponse(query []byte, config appConfig, store *codeStore) []byte {
	if len(query) < 12 {
		return nil
	}

	question, err := parseFirstQuestion(query)
	if err != nil {
		return makeDNSHeaderOnlyResponse(query, 1)
	}

	answerAddress := ""
	if question.QType == 1 && question.QClass == 1 {
		switch question.Name {
		case config.HealthDomain:
			answerAddress = config.HealthAddress
		case config.CodeDomain:
			answerAddress = codeToAddressOrEmpty(store.get(), config.EmptyAddress)
		default:
			answerAddress = config.DefaultDNSReply
		}
	}

	response := bytes.NewBuffer(make([]byte, 0, 64))
	response.Write(query[:2])
	response.Write([]byte{0x84, 0x00})
	response.Write([]byte{0x00, 0x01})
	if answerAddress == "" {
		response.Write([]byte{0x00, 0x00})
	} else {
		response.Write([]byte{0x00, 0x01})
	}
	response.Write([]byte{0x00, 0x00})
	response.Write([]byte{0x00, 0x00})
	response.Write(query[12:question.RawEnd])

	if answerAddress != "" {
		ip := net.ParseIP(answerAddress).To4()
		if ip == nil {
			ip = net.ParseIP(config.DefaultDNSReply).To4()
		}
		response.Write([]byte{0xc0, 0x0c})
		response.Write([]byte{0x00, 0x01})
		response.Write([]byte{0x00, 0x01})
		writeUint32(response, config.DNSTTLSeconds)
		response.Write([]byte{0x00, 0x04})
		response.Write(ip)
	}

	return response.Bytes()
}

func parseFirstQuestion(packet []byte) (dnsQuestion, error) {
	if len(packet) < 12 {
		return dnsQuestion{}, fmt.Errorf("packet too short")
	}
	qdCount := binary.BigEndian.Uint16(packet[4:6])
	if qdCount == 0 {
		return dnsQuestion{}, fmt.Errorf("no question")
	}

	offset := 12
	labels := []string{}
	for {
		if offset >= len(packet) {
			return dnsQuestion{}, fmt.Errorf("name overrun")
		}
		length := int(packet[offset])
		offset++
		if length == 0 {
			break
		}
		if length&0xc0 != 0 {
			return dnsQuestion{}, fmt.Errorf("compressed question name unsupported")
		}
		if length > 63 || offset+length > len(packet) {
			return dnsQuestion{}, fmt.Errorf("invalid label")
		}
		labels = append(labels, strings.ToLower(string(packet[offset:offset+length])))
		offset += length
	}

	if offset+4 > len(packet) {
		return dnsQuestion{}, fmt.Errorf("question overrun")
	}
	qType := binary.BigEndian.Uint16(packet[offset : offset+2])
	qClass := binary.BigEndian.Uint16(packet[offset+2 : offset+4])
	offset += 4

	return dnsQuestion{
		Name:   cleanDomain(strings.Join(labels, ".")),
		RawEnd: offset,
		QType:  qType,
		QClass: qClass,
	}, nil
}

func makeDNSHeaderOnlyResponse(query []byte, rcode byte) []byte {
	if len(query) < 12 {
		return nil
	}
	response := make([]byte, 12)
	copy(response[:2], query[:2])
	response[2] = 0x84
	response[3] = rcode & 0x0f
	return response
}

func writeUint32(buffer *bytes.Buffer, value uint32) {
	var bytes [4]byte
	binary.BigEndian.PutUint32(bytes[:], value)
	buffer.Write(bytes[:])
}

func codeToAddressOrEmpty(code string, empty string) string {
	if !codePattern.MatchString(code) {
		return empty
	}
	value, err := strconv.Atoi(code)
	if err != nil || value <= 0 || value > 999999 {
		return empty
	}
	x := value / 10000
	y := (value / 100) % 100
	z := value % 100
	return fmt.Sprintf("1.%d.%d.%d", x, y, z)
}

func normalizeCode(code string) string {
	code = strings.TrimSpace(code)
	code = strings.ReplaceAll(code, " ", "")
	return code
}

func cleanDomain(value string) string {
	value = strings.TrimSpace(strings.ToLower(value))
	value = strings.TrimSuffix(value, ".")
	return value
}

func env(key string, fallback string) string {
	value := strings.TrimSpace(os.Getenv(key))
	if value == "" {
		return fallback
	}
	return value
}

func writeJSON(w http.ResponseWriter, status int, payload map[string]any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		log.Printf("failed to write json: %v", err)
	}
}

func init() {
	for _, value := range []string{
		env("HEALTH_ADDRESS", "1.255.255.255"),
		env("EMPTY_ADDRESS", "0.0.0.0"),
		env("DEFAULT_DNS_REPLY", "0.0.0.0"),
	} {
		if ip := net.ParseIP(value); ip == nil || ip.To4() == nil {
			log.Fatalf("%s must be an IPv4 address", value)
		}
	}
}
