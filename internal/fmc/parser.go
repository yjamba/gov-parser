package fmc

import (
	"fmt"
	"gov-parser/internal/models"
	"io"
	"strings"

	"github.com/PuerkitoBio/goquery"
)

type Parser struct{}

func NewParser() *Parser {
	return &Parser{}
}

func (p *Parser) Parse(r io.Reader) ([]models.Tender, error) {
	doc, err := goquery.NewDocumentFromReader(r)
	if err != nil {
		return nil, fmt.Errorf("не удалось прочитать HTML: %w", err)
	}

	var lots []models.Tender

	doc.Find(".panel.panel-default").Each(func(i int, s *goquery.Selection) {
		rawTitle := s.Find(".panel-heading h4").Text()

		rawTitle = strings.TrimSpace(rawTitle)
		lotNumber := strings.Replace(rawTitle, "Просмотр объявления № ", "", 1)
		lotNumber = strings.TrimSpace(lotNumber)

		if lotNumber != "" {
			lot := models.Tender{
				External_advert_id: lotNumber,
			}
			lots = append(lots, lot)
		}
	})

	return lots, nil
}
