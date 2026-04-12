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

func (p *Parser) ParseAnnouncements(r io.Reader) ([]models.Tender, error) {
	doc, err := goquery.NewDocumentFromReader(r)
	if err != nil {
		return nil, fmt.Errorf("не удалось прочитать HTML: %w", err)
	}

	var announcements []models.Tender

	doc.Find("table.table-bordered tr").Each(func(i int, s *goquery.Selection) {
		cells := s.Find("td")

		if cells.Length() < 10 {
			return
		}
		externalid := cells.Eq(0).Text()
		externalid = strings.TrimSpace(externalid)
		cleanexternalid := strings.Split(externalid, "-")
		cleanid := cleanexternalid[0]

		name := cells.Eq(2).Find("div").First().Text()
		name = strings.TrimSpace(name)
		orgname := cells.Eq(1).Text()
		orgname = strings.TrimSpace(orgname)
		publishdate := cells.Eq(5).Text()
		startdate := cells.Eq(6).Text()
		price := cells.Eq(8).Text()

		if name != "" {
			lot := models.Tender{
				ExternalAdvertID: cleanid,
				Name:             name,
				OrganizerName:    orgname,
				PublishDate:      publishdate,
				StartDate:        startdate,
				Price:            price,
			}
			announcements = append(announcements, lot)
		}
	})

	return announcements, nil
}

func (p *Parser) ParseLots(r io.Reader) ([]models.Tender, error) {
	doc, err := goquery.NewDocumentFromReader(r)
	if err != nil {
		return nil, fmt.Errorf("не удалось прочитать HTML: %w", err)
	}

	var lots []models.Tender

	tableCount := doc.Find("table.table-bordered").Length()
	fmt.Printf("[ОТЛАДКА] Найдено таблиц с классом table-bordered: %d\n", tableCount)

	doc.Find("table.table-bordered tr").Each(func(i int, s *goquery.Selection) {
		if s.Find("th").Length() > 0 {
			fmt.Printf("[ОТЛАДКА] Строка %d: Пропускаем шапку таблицы\n", i)
			return
		}

		cells := s.Find("td")
		fmt.Printf("[ОТЛАДКА] Строка %d: Найдено колонок (td): %d\n", i, cells.Length())

		// Если колонок меньше 10, выведем HTML этой строки, чтобы понять, что не так
		if cells.Length() < 10 {
			html, _ := s.Html()
			fmt.Printf("[ОТЛАДКА] Строка %d пропущена. Слишком мало колонок. Ее HTML: %s\n", i, html)
			return
		}

		lotLink := cells.Eq(1).Find("a")
		lotNumber, _ := lotLink.Attr("data-lot-id")

		fmt.Printf("[ОТЛАДКА] Строка %d: Вытащили ID: '%s', Номер: '%s'\n", i, lotNumber)

		if lotNumber != "" {
			lot := models.Tender{
				ExternalAdvertID: lotNumber,
			}
			lots = append(lots, lot)
		}
	})

	return lots, nil
}
