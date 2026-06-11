# Portfolio

A personal portfolio website built with **Django 6.0** and **Bootstrap 5**.
Content is managed via JSON files — no database required.

## Features

- **Carousel-based presentation** — browse sections (home, about,
  portfolio, experience, education, skills, contact) in a single page
  with auto-play and pause/resume controls.
- **Project detail pages** — each project in the portfolio has its own
  dedicated view.
- **CV download** — one-click download of your CV as a static PDF file
  (`CV_PSS.pdf`).
- **Environment-aware content** — use `{{ VAR_NAME }}` placeholders in
  JSON files to inject environment variables.
- **Fully responsive** — built with Bootstrap 5 and Bootstrap Icons.

## Project structure

```
portfolio/
├── portfolio/               # Django project settings
│   ├── settings.py
│   └── urls.py
├── portapp/                 # Main application
│   ├── views.py
│   ├── context_processors.py
│   ├── data/                # JSON data files (content)
│   │   ├── about.json
│   │   ├── contact.json
│   │   ├── education.json
│   │   ├── experience.json
│   │   ├── home.json
│   │   ├── portfolio.json
│   │   └── skills.json
│   └── templates/
│       └── portapp/
│           ├── base.html
│           ├── home.html
│           ├── partials/    # Carousel slide partials
│           │   ├── _about.html
│           │   ├── _contact.html
│           │   ├── _education.html
│           │   ├── _experience.html
│           │   ├── _home.html
│           │   ├── _portfolio.html
│           │   └── _skills.html
│           └── ...          # Full-page templates
├── static/                  # Static files (place CV_PSS.pdf here)
├── db.sqlite3               # Only used for Django internals (sessions)
└── manage.py
```

## Quick start

```bash
# 1. Clone the repository
git clone https://github.com/youruser/portfolio.git
cd portfolio

# 2. Create and activate a virtual environment
python -m venv venv
source venv/bin/activate

# 3. Install dependencies
pip install -r portfolio/requirements.txt

# 4. Configure environment variables
cp env.example .env
# Then edit .env with your personal settings

# 5. Place your CV as a PDF
#     cp /path/to/your/CV.pdf static/CV_PSS.pdf

# 6. Run the development server
python manage.py runserver
```

Open [http://127.0.0.1:8000](http://127.0.0.1:8000) in your browser.

## Customisation

### Content

All content lives inside `portapp/data/` as JSON files. Edit them to
update your personal information, projects, experience, education,
skills, and contact details.

### Environment variables

Any `{{ VAR_NAME }}` placeholder inside a JSON value is automatically
replaced with the corresponding environment variable at runtime.
If the variable is not set, the placeholder is left as-is.

### Layout

Templates use Bootstrap 5. Override `base.html` or modify the partials
inside `templates/portapp/partials/` to change the carousel slides.

### CV

Place your PDF CV at `static/CV_PSS.pdf`. The download link in both the
navbar and the carousel will serve it as a file download.

## Production Deployment

When deploying to production, the following security settings **must** be
configured via the `.env` file:

| Variable | Recommended value | Purpose |
|---|---|---|
| `DJANGO_SECRET_KEY` | A strong random key | Signs sessions, CSRF tokens, and other cryptographic data. Generate one with `python -c "from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())"`. |
| `DJANGO_DEBUG` | `False` | Disables verbose error pages that could leak source code or configuration. |
| `DJANGO_ALLOWED_HOSTS` | Your domain(s) | Prevents HTTP Host header attacks. Example: `example.com,www.example.com`. |
| `SECURE_HSTS_SECONDS` | `31536000` | Enables HTTP Strict Transport Security for one year, forcing browsers to always use HTTPS. |
| `SECURE_SSL_REDIRECT` | `True` | Redirects all HTTP requests to HTTPS. |
| `SESSION_COOKIE_SECURE` | `True` | Ensures session cookies are only sent over HTTPS. |
| `CSRF_COOKIE_SECURE` | `True` | Ensures CSRF cookies are only sent over HTTPS. |

### Additional production hardening

1. **Reverse proxy** — Place nginx or Apache in front of Django to:
   - Terminate TLS/SSL.
   - Set the `Content-Security-Policy` header (the built-in middleware
     provides a sensible default, but a reverse proxy can fine-tune it).
   - Enable rate limiting to protect the admin panel and CV download
     endpoint against brute force.

2. **Serve static files** — Use the reverse proxy or a CDN to serve
   `staticfiles/` (collected via `python manage.py collectstatic`).

3. **Database** — Replace SQLite with PostgreSQL for better concurrency
   and reliability in production.

4. **Logging** — Configure Django's logging to send warnings and errors
   to a central monitoring system. The `AuditLogMiddleware` already logs
   CV downloads and 4xx/5xx responses via the `portapp` logger.

5. **Monitor CV download** — The `/cv/` endpoint is logged by
   `AuditLogMiddleware`. Review those logs periodically to detect
   unusual activity.

## License

MIT
