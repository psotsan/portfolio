# settings.py - CORREGIDO

import os
from pathlib import Path

import environ

BASE_DIR = Path(__file__).resolve().parent.parent

env = environ.Env()
environ.Env.read_env(BASE_DIR / ".env")

SECRET_KEY = env(
    "DJANGO_SECRET_KEY",
    default="django-insecure-change-in-production",
)
DEBUG = env.bool("DJANGO_DEBUG", default=False)
ALLOWED_HOSTS = env.list(
    "DJANGO_ALLOWED_HOSTS",
    default=["localhost", "127.0.0.1"],
)

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'portapp',
]

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',      
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    # Custom security & audit middleware (order matters: keep after
    # SecurityMiddleware so its headers take precedence).
    'portapp.middleware.CSPMiddleware',
    'portapp.middleware.AuditLogMiddleware',
]

ROOT_URLCONF = 'portfolio.urls'

TEMPLATES = [
    {
        'BACKEND': 'django.template.backends.django.DjangoTemplates',
        'DIRS': [],
        'APP_DIRS': True,
        'OPTIONS': {
            'context_processors': [
                'django.template.context_processors.debug',
                'django.template.context_processors.request',
                'django.contrib.auth.context_processors.auth',
                'django.contrib.messages.context_processors.messages',
                'portapp.context_processors.personal_info',
            ],
        },
    },
]

WSGI_APPLICATION = 'portfolio.wsgi.application'

DATABASES = {  
    'default': {
        'ENGINE': 'django.db.backends.sqlite3',
        'NAME': BASE_DIR / 'db.sqlite3',
    }
}

# =============================================================================
# SECURITY
# =============================================================================

# -- HSTS (HTTP Strict Transport Security) -----------------------------------
# In production, set SECURE_HSTS_SECONDS=31536000 (1 year) via .env
SECURE_HSTS_SECONDS = env.int("SECURE_HSTS_SECONDS", default=0)
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True

# -- SSL / HTTPS -------------------------------------------------------------
# In production, set SECURE_SSL_REDIRECT=True via .env
SECURE_SSL_REDIRECT = env.bool("SECURE_SSL_REDIRECT", default=False)
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# -- Secure cookies ----------------------------------------------------------
# In production, set both to True via .env
SESSION_COOKIE_SECURE = env.bool("SESSION_COOKIE_SECURE", default=False)
CSRF_COOKIE_SECURE = env.bool("CSRF_COOKIE_SECURE", default=False)

# -- Content-Type Protection -------------------------------------------------
SECURE_CONTENT_TYPE_NOSNIFF = True

# -- Referrer Policy ---------------------------------------------------------
SECURE_REFERRER_POLICY = "same-origin"

# -- CSP delivered via middleware (see CSPMiddleware in portapp/middleware.py)
# The Content-Security-Policy is set as an HTTP header by CSPMiddleware.
# The meta-tag fallback has been removed from base.html because meta tags
# cannot enforce frame-ancestors, form-action, or sandbox directives.
# In production, consider setting this header at the reverse-proxy level
# (nginx, Apache) for better performance.

# =============================================================================
# LOGGING
# =============================================================================

import pathlib

LOG_DIR = BASE_DIR / "logs"
pathlib.Path(LOG_DIR).mkdir(exist_ok=True)

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "formatters": {
        "verbose": {
            "format": (
                "{levelname} {asctime} {module} {process:d} {thread:d} "
                "{message}"
            ),
            "style": "{",
        },
        "simple": {
            "format": "{levelname} {message}",
            "style": "{",
        },
    },
    "handlers": {
        "console": {
            "class": "logging.StreamHandler",
            "formatter": "simple",
        },
        "file": {
            "class": "logging.handlers.RotatingFileHandler",
            "filename": LOG_DIR / "portfolio.log",
            "maxBytes": 5 * 1024 * 1024,  # 5 MB
            "backupCount": 3,
            "formatter": "verbose",
        },
    },
    "loggers": {
        "portapp": {
            "handlers": ["console", "file"],
            "level": "INFO",
            "propagate": False,
        },
        "django": {
            "handlers": ["console", "file"],
            "level": "INFO",
            "propagate": False,
        },
        "django.request": {
            "handlers": ["console", "file"],
            "level": "WARNING",
            "propagate": False,
        },
    },
}

# =============================================================================
# STATIC
# =============================================================================

STATIC_URL = 'static/'
STATIC_ROOT = BASE_DIR / 'staticfiles'
STATICFILES_DIRS = [
    BASE_DIR / "static",
]

# =============================================================================
# MISC
# =============================================================================

DEFAULT_AUTO_FIELD = 'django.db.models.BigAutoField'