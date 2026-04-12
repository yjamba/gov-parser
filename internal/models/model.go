package models

type Tender struct {
	ExternalAdvertID      string  `json:"external_advert_id"`
	Name                  string  `json:"name"`
	URL                   string  `json:"url"`
	LotNumber             string  `json:"lot_number"`
	OrganizerName         string  `json:"organizer_name"`
	
	// Даты пока оставляем строками для удобства вывода в консоль, 
	// но перед записью в БД их нужно будет парсить в time.Time
	PublishDate           string  `json:"publish_date"` 
	StartDate             string  `json:"start_date"`
	EndDate               string  `json:"end_date"`
	
	Price                 string `json:"price"` 
	CurrencyCode          string  `json:"currency_code"`
	
	TechDescriptionParsed bool    `json:"tech_description_parsed"`
	IsMLProcessed         bool    `json:"is_ml_processed"`
	
	Address               string  `json:"address"`
	DownloadURL           string  `json:"download_url"`
	CreatedAt             string  `json:"created_at"`
	SourceRowNum          int     `json:"source_row_num"`
}