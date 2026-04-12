package crawler

import (
	"fmt"
	"gov-parser/internal/fmc"
	"gov-parser/internal/models"
	"log"
	"net/http"
	"time"
)

type Scraper struct {
	client *http.Client
	parser *fmc.Parser
}

func NewScraper(p *fmc.Parser) *Scraper {
	return &Scraper{
		client: &http.Client{Timeout: 15 * time.Second},
		parser: p,
	}
}

func (s *Scraper) fetchHTML(url string) (*http.Response, error) {
	req, err := http.NewRequest("GET", url, nil)
	if err != nil {
		return nil, err
	}

	req.Header.Set("User-Agent", "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
	req.Header.Set("Accept", "text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,*/*;q=0.8")
	req.Header.Set("Accept-Language", "ru-RU,ru;q=0.9,en-US;q=0.8,en;q=0.7")
	return s.client.Do(req)
}

func (s *Scraper) Run(searchURL string) ([]models.Tender, error) {
	resp, err := s.fetchHTML(searchURL)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	announcements, err := s.parser.ParseAnnouncements(resp.Body)
	if err != nil {
		return nil, err
	}
	var allTenders []models.Tender

	for _, ann := range announcements {
		lotsUrl := fmt.Sprintf("https://fms.ecc.kz/ru/lots?advertId=%s", ann.LotNumber)
		lotsResp, err := s.fetchHTML(lotsUrl)
		if err != nil {
			log.Printf("Ошибка загрузки лотов для %s: %v", ann.LotNumber, err)
			continue
		}
		lots, err := s.parser.ParseLots(lotsResp.Body)
		lotsResp.Body.Close()
		if err != nil {
			log.Printf("Ошибка парсинга лотов для %s: %v", ann.ExternalAdvertID, err)
			continue
		}

		for i := range lots {
			lots[i].ExternalAdvertID = ann.ExternalAdvertID

			allTenders = append(allTenders, lots...)

			// Вежливая пауза
			time.Sleep(2 * time.Second)
		}

	}

	return allTenders, nil
}
