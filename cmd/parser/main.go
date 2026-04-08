package main

import (
	"encoding/json"
	"fmt"
	"gov-parser/internal/fmc"
	"log"
	"net/http"
)

func main() {
	targetUrl := "https://fms.ecc.kz/ru/announce/index/518384"

	resp, err := http.Get(targetUrl)
	if err != nil {
		fmt.Println(err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		fmt.Println("Status code is not 200")
		log.Fatalf("Status code is not 200")
	}

	parser := fmc.NewParser()

	lots, err := parser.Parse(resp.Body)
	if err != nil {
		fmt.Println(err)
	}

	prettyJson, err := json.MarshalIndent(lots, "", "  ")
	if err != nil {
		fmt.Println(err)
	}

	fmt.Println(string(prettyJson))
}
