import json
import os
import re
from pathlib import Path

from django.conf import settings


def _load_home_json() -> dict:
    filepath = Path(settings.BASE_DIR) / "portapp" / "data" / "home.json"
    try:
        with open(filepath, encoding="utf-8") as f:
            return json.load(f)
    except (FileNotFoundError, json.JSONDecodeError):
        return {}


def personal_info(request):
    home_data = _load_home_json()
    cv_fn = home_data.get("cv_filename", "CV_PSS.pdf")
    # Sanitize against path traversal and XSS
    cv_fn = Path(cv_fn).name
    if not re.match(r'^[\w\-. ]+$', cv_fn):
        cv_fn = "CV_PSS.pdf"
    return {
        "PERSONAL_NAME": os.environ.get("PERSONAL_NAME")
                         or home_data.get("name", "Tu Nombre"),
        "PERSONAL_EMAIL": os.environ.get("PERSONAL_EMAIL")
                          or "tu@email.com",
        "PERSONAL_GITHUB": os.environ.get("PERSONAL_GITHUB")
                           or "https://github.com/tuusuario",
        "PERSONAL_LINKEDIN": os.environ.get("PERSONAL_LINKEDIN")
                             or "https://linkedin.com/in/tuusuario",
        "CV_FILENAME": cv_fn,
    }
