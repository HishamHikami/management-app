"""Every Django user gets a Member, including accounts made with `createsuperuser` or in the admin."""


def ensure_member(sender, instance, created, **kwargs):
    if not created or kwargs.get("raw"):
        return
    from .models import Member

    if not Member.objects.filter(user=instance).exists():
        Member.objects.create(
            user=instance,
            name=instance.get_full_name() or instance.first_name or instance.username,
            level="super" if instance.is_superuser else "",
        )
