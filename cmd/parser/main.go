package main

import (
	"encoding/json"
	"fmt"
	"gov-parser/internal/crawler"
	"gov-parser/internal/fmc"
	"log"
)

func main() {
	targetUrl := "https://fms.ecc.kz/ru/searchanno"

	parser := fmc.NewParser()
	scraper := crawler.NewScraper(parser)

	alltenders, err := scraper.Run(targetUrl)
	if err != nil {
		log.Fatalf("Ошибка запуска скрейпера: %v", err)
	}

	// 6. Красивый вывод
	prettyJson, err := json.MarshalIndent(alltenders, "", "  ")
	if err != nil {
		log.Fatalf("Ошибка сборки JSON: %v", err)
	}

	fmt.Println(string(prettyJson))
}
