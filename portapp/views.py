import json
import os
import re
from pathlib import Path

from django.conf import settings
from django.http import FileResponse, Http404
from django.shortcuts import render

_ALLOWED_JSON_FILES = frozenset({
    "home.json", "about.json", "portfolio.json",
    "experience.json", "education.json", "skills.json",
    "contact.json",
})

# Whitelist of allowed slugs for template inclusion in the home view.
# This prevents Server-Side Template Inclusion attacks if slug values
# were ever sourced from user-controllable data.
_ALLOWED_SLUGS = frozenset({
    "home", "about", "portfolio", "experience",
    "education", "skills", "contact",
})


def _load_json(filename: str) -> dict:
    if filename not in _ALLOWED_JSON_FILES:
        raise ValueError(f"Access denied to: {filename}")
    filepath = Path(settings.BASE_DIR) / "portapp" / "data" / filename
    with open(filepath, encoding="utf-8") as f:
        return json.load(f)


def _resolve_env(data: any) -> dict:
    """Replace {{ VAR }} for env vars"""
    def _replace(match):
        var_name = match.group(1)
        return os.environ.get(var_name, match.group(0))
    if isinstance(data, str):
        return re.sub(r"\{\{\s*(\w+)\s*\}\}", _replace, data)
    if isinstance(data, dict):
        return {k: _resolve_env(v) for k, v in data.items()}
    if isinstance(data, list):
        return [_resolve_env(v) for v in data]
    return data


def home(request):
    sections = [
        _load_json("home.json"),
        _load_json("about.json"),
        _load_json("portfolio.json"),
        _load_json("experience.json"),
        _load_json("education.json"),
        _load_json("skills.json"),
        _load_json("contact.json"),
    ]
    slugs = [
        "home", "about", "portfolio", "experience",
        "education", "skills", "contact",
    ]
    icons = [
        "bi-house-fill", "bi-person-fill", "bi-briefcase-fill",
        "bi-laptop", "bi-book-fill", "bi-gear-fill",
        "bi-envelope-fill",
    ]
    for section, slug, icon in zip(sections, slugs, icons):
        # Enforce whitelist — if a slug is ever not in _ALLOWED_SLUGS,
        # fall back to "home" to prevent arbitrary file inclusion.
        section["slug"] = slug if slug in _ALLOWED_SLUGS else "home"
        section["icon"] = icon
    sections = _resolve_env(sections)
    return render(request, "portapp/home.html", {"sections": sections})


def about(request):
    data = _resolve_env(_load_json("about.json"))
    return render(request, "portapp/about.html", {"data": data})


def portfolio_list(request):
    data = _resolve_env(_load_json("portfolio.json"))
    return render(request, "portapp/portfolio_list.html", {"data": data})


def project_detail(request, project_id: int):
    projects = _resolve_env(_load_json("portfolio.json")).get("projects", [])
    project = next((p for p in projects if p["id"] == project_id), None)
    if project is None:
        raise Http404("Proyecto no encontrado")
    return render(
        request,
        "portapp/project_detail.html",
        {"project": project},
    )


def experience(request):
    data = _resolve_env(_load_json("experience.json"))
    return render(request, "portapp/experience.html", {"data": data})


def education(request):
    data = _resolve_env(_load_json("education.json"))
    return render(request, "portapp/education.html", {"data": data})


def skills(request):
    data = _resolve_env(_load_json("skills.json"))
    return render(request, "portapp/skills.html", {"data": data})


def contact(request):
    data = _resolve_env(_load_json("contact.json"))
    return render(request, "portapp/contact.html", {"data": data})


def download_cv(request):
    home_path = Path(settings.BASE_DIR) / "portapp" / "data" / "home.json"
    try:
        with open(home_path, encoding="utf-8") as f:
            cv_fn = json.load(f).get("cv_filename", "CV_PSS.pdf")
    except (FileNotFoundError, json.JSONDecodeError):
        cv_fn = "CV_PSS.pdf"
    # Sanitise filename against path traversal
    cv_fn = Path(cv_fn).name
    if not re.match(r'^[\w\-. ]+$', cv_fn):
        cv_fn = "CV_PSS.pdf"
    pdf_path = Path(settings.BASE_DIR) / "static" / cv_fn
    if not pdf_path.exists():
        raise Http404("CV no encontrado")
    # Use a context manager so the file descriptor is always closed,
    # even if an exception occurs before FileResponse processes it.
    with open(pdf_path, "rb") as f:
        return FileResponse(
            f,
            as_attachment=True,
            filename=cv_fn,
            content_type="application/pdf",
        )
