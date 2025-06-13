# Amateur Radio Logbook

This is a web-based Amateur Radio Logbook application built using [Mojolicious](https://mojolicious.org/) and SQLite.
It allows operators to log QSOs (contacts), visualize worked grids and DXCCs, and generate printable QSL cards with support for custom logos.

## Features

### ✅ Core Logbook Functionality
- Log, edit, and delete QSOs
- Filter by date, band, mode, DXCC, grid, etc.
- Sortable and reorderable columns with persistent local storage

### 🗺 QSO Map Heatmap
- Map of worked/unworked Maidenhead grid squares
- Overlay of DXCC entities with confirmation status
- Supports band/mode/date filtering
- Export map snapshot as PNG
- URL: `/qso_map`

### 📅 Calendar View
- Monthly calendar display of QSOs
- Shows QSO counts or DXCC flags by day
- Built using FullCalendar.js
- URL: `/calendar`

### 🖨 QSL Card PDF Generation
- Generate printable PDF QSL cards per QSO or in batch
- Includes frequency, RST, grid, DXCC, and notes
- Auto-includes your uploaded logo
- Supports label-sized layouts (3.5" x 5")
- URL: `/generate_qsl_pdf`

### 🖼 Logo Upload
- Upload and manage a custom logo
- Used in QSL PDF output
- URL: `/upload_logo`

## Setup

```bash
cpan Mojolicious DBD::SQLite PDF::API2
