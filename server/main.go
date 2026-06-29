package main

import (
	"flag"
	"log"

	"server-storage-management-system/server/api"
	"server-storage-management-system/server/database"
	"server-storage-management-system/server/service"
)

func main() {
	// 管理后台入口：解析运行参数，初始化 SQLite，然后启动 Gin HTTP 服务。
	addr := flag.String("addr", ":8080", "HTTP listen address")
	dbPath := flag.String("db", "server-storage.db", "SQLite database path")
	flag.Parse()

	db, err := database.Open(*dbPath)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	store := service.NewStore(db)
	authConfig, err := api.AuthConfigFromEnv()
	if err != nil {
		log.Fatal(err)
	}
	if authConfig.Enabled {
		log.Printf("web admin authentication enabled for user %s", authConfig.Username)
	} else {
		log.Print("web admin authentication disabled")
	}
	router := api.NewRouterWithAuth(store, authConfig)

	log.Printf("management server listening on %s", *addr)
	if err := router.Run(*addr); err != nil {
		log.Fatal(err)
	}
}
