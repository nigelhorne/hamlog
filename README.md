# 📡 Amateur Radio Logbook

A web-based Amateur Radio Logbook built with [Mojolicious](https://mojolicious.org/), SQLite, and Leaflet.js. It supports QSO logging, mapping worked grids/DXCCs, calendar visualization, and printable QSL card generation.

![Preview Map](public/screenshots/qso_map_preview.png)

## 🌟 Features

### QSO Management
- Add/edit/delete QSOs
- Frequency, band, mode, grid, RST, DXCC, notes
- Persistent sortable and reorderable table columns

### 🗺 Grid & DXCC Mapping
- Visualize worked/unworked **Maidenhead grid squares**
- Overlay **DXCC entities** (confirmed vs unconfirmed)
- Filter by band, mode, and date
- Exportable map as PNG
- [`/qso_map`](http://localhost:3000/qso_map)

### 📅 Calendar View
- Calendar of QSOs using FullCalendar
- Hover or click for DXCC details
- [`/calendar`](http://localhost:3000/calendar)

### 🖨 PDF QSL Card Generator
- Generate printable **QSL cards**
- Includes frequency, mode, RST, DXCC, and your logo
- Auto layout for 3.5" x 5" envelope formats
- [`/generate_qsl_pdf`](http://localhost:3000/generate_qsl_pdf)

### 🖼 Custom Logo Upload
- Upload a station logo
- Used automatically in QSL PDFs
- [`/upload_logo`](http://localhost:3000/upload_logo)

---

## 🚀 Getting Started

### Prerequisites

Install dependencies:

```bash
cpan Mojolicious DBD::SQLite PDF::API2
````

Clone this repo:

```bash
git clone https://github.com/nigelhorne/hamlog.git
cd hamlog
```

### Database Setup

Ensure you have an SQLite database with a `log` table:

```sql
CREATE TABLE log (
  id INTEGER PRIMARY KEY,
  call TEXT,
  date TEXT,
  time TEXT,
  frequency TEXT,
  mode TEXT,
  rst_sent TEXT,
  rst_recv TEXT,
  grid TEXT,
  dxcc TEXT,
  notes TEXT
);
```

Add some sample data or import from ADIF/CSV.

---

## 📂 File Structure

```
hamlog/
├── hamlog.pl                  # Mojolicious app
├── templates/
│   ├── qso_map.html.ep        # Heatmap + DXCC overlay
│   ├── calendar.html.ep       # Calendar view
│   └── layouts/default.html.ep
├── public/
│   └── uploads/logo.jpg       # Your station logo
├── logbook.db                 # SQLite database
└── README.md
```

---

## 🧪 Running the App

```bash
morbo hamlog.pl
```

Visit [http://localhost:3000](http://localhost:3000) in your browser.

---

## 🧩 Roadmap Ideas

* ADIF import/export
* Award tracking (e.g. WAS, DXCC progress)
* User authentication
* Remote QTH mapping
* QSL bureau mailing labels

---

## 🤝 Contributing

Pull requests are welcome! For major changes, please open an issue first.

---

## 🛡 License

GPL2 © 2025 Nigel Horne

```

---
