// pinger: a tiny uptime check for the allcsvideos status page.
// It prints the time in Mumbai and checks that an HTTPS site answers.
package main

import (
	"fmt"
	"net/http"
	"os"
	"time"
)

func main() {
	loc, err := time.LoadLocation("Asia/Kolkata")
	if err != nil {
		fmt.Println("timezone error:", err)
	} else {
		fmt.Println("Mumbai time:", time.Now().In(loc).Format("15:04 MST"))
	}
	client := http.Client{Timeout: 5 * time.Second}
	resp, err := client.Get("https://example.com/")
	if err != nil {
		fmt.Println("check failed:", err)
		os.Exit(1)
	}
	fmt.Println("https://example.com/ ->", resp.Status)
}
