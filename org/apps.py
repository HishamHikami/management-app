from django.apps import AppConfig


class OrgConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    name = "org"
    verbose_name = "Organization"

    def ready(self):
        from django.contrib.auth.models import User
        from django.db.models.signals import post_save

        def ensure_member(sender, instance, created, **kwargs):
            # Accounts made with `createsuperuser` or the Django admin get a Member too.
            if created and not kwargs.get("raw"):
                from .models import Member

                if not Member.objects.filter(user=instance).exists():
                    Member.objects.create(
                        user=instance,
                        name=instance.get_full_name() or instance.first_name or instance.username,
                        is_admin=instance.is_superuser,
                    )

        post_save.connect(ensure_member, sender=User, dispatch_uid="org-ensure-member")
