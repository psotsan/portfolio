import logging
import time

logger = logging.getLogger(__name__)


class CSPMiddleware:
    """Deliver Content-Security-Policy via HTTP header.

    The meta-tag CSP has been removed from base.html because meta tags
    cannot enforce frame-ancestors, form-action, or sandbox directives.
    The HTTP header set here is the authoritative policy.  In production,
    consider moving this to the reverse proxy (nginx, Apache) for better
    performance.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        response = self.get_response(request)
        csp = (
            "default-src 'self'; "
            "style-src 'self' https://cdn.jsdelivr.net https://fonts.googleapis.com; "
            "script-src 'self' https://cdn.jsdelivr.net; "
            "font-src 'self' https://cdn.jsdelivr.net https://fonts.gstatic.com; "
            "img-src 'self' data:; "
            "frame-ancestors 'none'; "
            "base-uri 'self'; "
            "form-action 'self'"
        )
        response["Content-Security-Policy"] = csp
        return response


class AuditLogMiddleware:
    """Log selected requests for audit purposes.

    Logs CV downloads and any 4xx/5xx responses so that suspicious
    activity can be reviewed later.
    """

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        start = time.time()
        response = self.get_response(request)
        duration = time.time() - start

        path = request.path
        method = request.method
        status = response.status_code

        # Log CV download attempts
        if path == "/cv/":
            logger.info(
                "CV download — method=%s status=%s ip=%s agent=%s",
                method, status, self._client_ip(request),
                request.META.get("HTTP_USER_AGENT", ""),
            )

        # Log client errors (4xx) and server errors (5xx)
        if 400 <= status < 600:
            logger.warning(
                "HTTP %s — method=%s path=%s status=%s ip=%s duration=%.2fs",
                status, method, path, status,
                self._client_ip(request), duration,
            )

        return response

    @staticmethod
    def _client_ip(request):
        xff = request.META.get("HTTP_X_FORWARDED_FOR")
        if xff:
            return xff.split(",")[0].strip()
        return request.META.get("REMOTE_ADDR", "")
