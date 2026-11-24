from functools import wraps

from django.conf import settings
from django.core.cache import cache
from django.http import HttpResponse
from django.shortcuts import render


def home(request):
    return render(request, "org/home.html", {"org_name": settings.ORG_NAME, "short_name": settings.ORG_SHORT_NAME})


def _ctx():
    return {"org_name": settings.ORG_NAME, "short_name": settings.ORG_SHORT_NAME,
            "contact": settings.ORG_CONTACT_EMAIL}


def privacy(request):
    return render(request, "org/privacy.html", _ctx())


def account_deletion(request):
    return render(request, "org/account_deletion.html", _ctx())


def health(request):
    return HttpResponse("ok", content_type="text/plain")


def throttled_admin_login(view):
    """Wraps the Django admin login with the same per-IP lockout as the app login."""

    @wraps(view)
    def wrapper(request, *args, **kwargs):
        ip = request.META.get("HTTP_X_REAL_IP") or request.META.get("REMOTE_ADDR", "unknown")
        key = f"admin-login-fail:{ip}"
        if request.method == "POST" and cache.get(key, 0) >= settings.LOGIN_MAX_ATTEMPTS:
            return HttpResponse("Too many failed attempts. Try again later.", status=429)
        response = view(request, *args, **kwargs)
        if request.method == "POST" and not request.user.is_authenticated:
            cache.set(key, cache.get(key, 0) + 1, settings.LOGIN_LOCKOUT_SECONDS)
        return response

    return wrapper
