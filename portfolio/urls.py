from django.contrib import admin
from django.urls import path

from portapp import views

urlpatterns = [
    path("admin/", admin.site.urls),
    path("", views.home, name="home"),
    path("about/", views.about, name="about"),
    path("portfolio/", views.portfolio_list, name="portfolio_list"),
    path("portfolio/<int:project_id>/", views.project_detail,
         name="project_detail"),
    path("experience/", views.experience, name="experience"),
    path("education/", views.education, name="education"),
    path("skills/", views.skills, name="skills"),
    path("contact/", views.contact, name="contact"),
    path("cv/", views.download_cv, name="cv"),
]

