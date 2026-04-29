package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

type inboundPayload struct {
	Title   string `json:"title"`
	Message string `json:"message"`
}

type ntfyPayload struct {
	Topic    string `json:"topic"`
	Title    string `json:"title"`
	Message  string `json:"message"`
	Priority int    `json:"priority"`
}

var client = &http.Client{Timeout: 5 * time.Second}

func main() {
	port := getEnv("PORT", "4000")

	mux := http.NewServeMux()
	mux.HandleFunc("GET /health", handleHealth)
	mux.HandleFunc("POST /webhook", handleWebhook)

	log.Printf("bridge listening on :%s", port)
	if err := http.ListenAndServe(":"+port, mux); err != nil {
		log.Fatal(err)
	}
}

func handleHealth(w http.ResponseWriter, _ *http.Request) {
	_, err := w.Write([]byte("ok"))
	if err != nil {
		return
	}
}

func handleWebhook(w http.ResponseWriter, r *http.Request) {
	var p inboundPayload
	if err := json.NewDecoder(r.Body).Decode(&p); err != nil || p.Title == "" || p.Message == "" {
		http.Error(w, "bad request", http.StatusBadRequest)
		return
	}

	if err := forwardToNtfy(p.Title, p.Message); err != nil {
		log.Printf("ntfy forward failed: %v", err)
		http.Error(w, "upstream error encountered:", http.StatusBadGateway)
		return
	}

	_, err := w.Write([]byte("ok"))
	if err != nil {
		return
	}
}

func forwardToNtfy(title, message string) error {
	body, _ := json.Marshal(ntfyPayload{
		Topic:    getEnv("NTFY_TOPIC", "alerts"),
		Title:    title,
		Message:  message,
		Priority: 3,
	})

	req, err := http.NewRequest(http.MethodPost, getEnv("NTFY_URL", "http://ntfy:80/"), bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")
	if token := getEnv("NTFY_TOKEN", ""); token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}

	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer func() { _ = resp.Body.Close() }()

	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		body, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("ntfy returned %d: %s", resp.StatusCode, body)
	}

	return nil
}

func getEnv(key, fallback string) string {
	if v := os.Getenv(key); v != "" {
		return v
	}
	return fallback
}
