from django.apps import AppConfig


class OrgConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "org"
    verbose_name = "Organization"

    def ready(self):
        from django.contrib.auth.models import User
        from django.db.models.signals import post_save

        from .signals import ensure_member

        # weak=False: keep the receiver alive no matter how it is referenced.
        post_save.connect(ensure_member, sender=User, weak=False, dispatch_uid="org-ensure-member")
