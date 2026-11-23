from django.contrib import admin
from django.urls import include, path

from org import views

admin.site.site_header = "Organization admin"
admin.site.login = views.throttled_admin_login(admin.site.login)

urlpatterns = [
    path("", views.home, name="home"),
    path("health", views.health, name="health"),
    path("api/v1/", include("org.api_urls")),
    path("admin/", admin.site.urls),
]
