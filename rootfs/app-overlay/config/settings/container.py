"""Settings for the all-in-one Docker / Unraid image.

Upstream's production settings force HTTPS (redirect, HSTS, secure cookies),
which makes plain ``http://<unraid-ip>:8000`` unusable. Here those follow
APP_URL's scheme and can be overridden per variable.
"""

from urllib.parse import urlparse

from .production import *  # noqa: F401, F403
from .base import APP_URL, env

_app_url = urlparse(APP_URL)
_https = _app_url.scheme == "https"

SECURE_SSL_REDIRECT = env.bool("SECURE_SSL_REDIRECT", default=False)
SESSION_COOKIE_SECURE = env.bool("SESSION_COOKIE_SECURE", default=_https)
CSRF_COOKIE_SECURE = env.bool("CSRF_COOKIE_SECURE", default=_https)
SECURE_HSTS_SECONDS = env.int("SECURE_HSTS_SECONDS", default=31536000 if _https else 0)
SECURE_HSTS_INCLUDE_SUBDOMAINS = env.bool("SECURE_HSTS_INCLUDE_SUBDOMAINS", default=_https)
SECURE_HSTS_PRELOAD = env.bool("SECURE_HSTS_PRELOAD", default=False)

# Django 4+ checks the Origin header on POST; behind a reverse proxy or on a
# non-default port that only passes when the origin is trusted explicitly.
CSRF_TRUSTED_ORIGINS = env.list("CSRF_TRUSTED_ORIGINS", default=[])
if _app_url.scheme and _app_url.netloc:
    _origin = f"{_app_url.scheme}://{_app_url.netloc}"
    if _origin not in CSRF_TRUSTED_ORIGINS:
        CSRF_TRUSTED_ORIGINS.append(_origin)

LOGGING["root"]["level"] = env("LOG_LEVEL", default="WARNING")  # noqa: F405
