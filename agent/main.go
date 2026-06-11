package main

import (
	"bytes"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/shirou/gopsutil/v4/cpu"
	"github.com/shirou/gopsutil/v4/disk"
	"github.com/shirou/gopsutil/v4/mem"
)

type report struct {
	Name        string  `json:"name"`
	Address     string  `json:"address"`
	CPUUsage    float64 `json:"cpu_usage"`
	MemoryUsage float64 `json:"memory_usage"`
	DiskUsage   float64 `json:"disk_usage"`
}

func main() {
	serverURL := flag.String("server", "http://127.0.0.1:8080", "management server base URL")
	nodeName := flag.String("name", "", "node name, defaults to hostname")
	address := flag.String("address", "", "node address, defaults to first private IPv4")
	diskPath := flag.String("disk", "/", "disk path to monitor")
	interval := flag.Duration("interval", 30*time.Second, "report interval")
	once := flag.Bool("once", false, "send one report and exit")
	flag.Parse()

	if *nodeName == "" {
		hostname, err := os.Hostname()
		if err != nil {
			log.Fatal(err)
		}
		*nodeName = hostname
	}
	if *address == "" {
		*address = firstPrivateIPv4()
	}

	for {
		payload, err := collect(*nodeName, *address, *diskPath)
		if err != nil {
			log.Printf("collect metrics: %v", err)
		} else if err := send(*serverURL, payload); err != nil {
			log.Printf("send report: %v", err)
		} else {
			log.Printf("reported node=%s cpu=%.1f memory=%.1f disk=%.1f", payload.Name, payload.CPUUsage, payload.MemoryUsage, payload.DiskUsage)
		}

		if *once {
			return
		}
		time.Sleep(*interval)
	}
}

func collect(name, address, diskPath string) (report, error) {
	cpuUsage, err := cpu.Percent(time.Second, false)
	if err != nil {
		return report{}, err
	}
	memory, err := mem.VirtualMemory()
	if err != nil {
		return report{}, err
	}
	diskUsage, err := disk.Usage(diskPath)
	if err != nil {
		return report{}, err
	}

	value := 0.0
	if len(cpuUsage) > 0 {
		value = cpuUsage[0]
	}
	return report{
		Name:        name,
		Address:     address,
		CPUUsage:    value,
		MemoryUsage: memory.UsedPercent,
		DiskUsage:   diskUsage.UsedPercent,
	}, nil
}

func send(serverURL string, payload report) error {
	body, err := json.Marshal(payload)
	if err != nil {
		return err
	}
	endpoint := strings.TrimRight(serverURL, "/") + "/api/servers/report"
	req, err := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(body))
	if err != nil {
		return err
	}
	req.Header.Set("Content-Type", "application/json")

	client := http.Client{Timeout: 10 * time.Second}
	resp, err := client.Do(req)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		return fmt.Errorf("server returned %s", resp.Status)
	}
	return nil
}

func firstPrivateIPv4() string {
	addrs, err := net.InterfaceAddrs()
	if err != nil {
		return ""
	}
	for _, addr := range addrs {
		ipNet, ok := addr.(*net.IPNet)
		if !ok || ipNet.IP == nil || ipNet.IP.IsLoopback() {
			continue
		}
		ip := ipNet.IP.To4()
		if ip == nil {
			continue
		}
		if ip[0] == 10 || (ip[0] == 172 && ip[1] >= 16 && ip[1] <= 31) || (ip[0] == 192 && ip[1] == 168) {
			return ip.String()
		}
	}
	return ""
}
