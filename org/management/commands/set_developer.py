"""Turn an existing account into the hidden developer account (or back).

    deploy/manage.sh set_developer --list
    deploy/manage.sh set_developer you@example.com        # email, phone, username or #id
    deploy/manage.sh set_developer you@example.com --undo

The developer has full access, leaves every committee, and is hidden from the people list,
announcements, meeting invitations, pickers and stats. Others can't view or change it.
"""

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from org.models import Member, Membership


class Command(BaseCommand):
    help = "Make an account the hidden developer account."

    def add_arguments(self, parser):
        parser.add_argument("who", nargs="?", help="Email, phone, username or #id")
        parser.add_argument("--list", action="store_true", help="List accounts and exit.")
        parser.add_argument("--undo", action="store_true", help="Make it a normal account again.")
        parser.add_argument("--keep-committees", action="store_true")

    def _find(self, who):
        from org.api import find_user

        if who.startswith("#") and who[1:].isdigit():
            return Member.objects.filter(pk=int(who[1:])).first()
        user = find_user(who)
        return getattr(user, "member", None) if user else None

    @transaction.atomic
    def handle(self, *args, **o):
        if o["list"]:
            for m in Member.objects.select_related("user").order_by("pk"):
                flags = [f for f, on in (("developer", m.is_developer), ("admin", m.is_admin),
                                         ("inactive", not m.user.is_active)) if on]
                self.stdout.write(f"#{m.pk}  {m.name}  {m.user.email or '-'}  {m.phone or '-'}  {' '.join(flags)}")
            return
        if not o["who"]:
            raise CommandError("Say who: email, phone, username or #id (see --list).")
        m = self._find(o["who"])
        if m is None:
            raise CommandError(f"No account matches {o['who']!r}.")
        if o["undo"]:
            m.is_developer = False
            m.save()
            self.stdout.write(self.style.SUCCESS(f"{m.name} is a normal account again (admin: {m.is_admin})."))
            return
        m.is_developer = True
        m.is_admin = True
        m.save()
        left = 0
        if not o["keep_committees"]:
            left, _ = Membership.objects.filter(member=m).delete()
        self.stdout.write(self.style.SUCCESS(
            f"{m.name} (#{m.pk}) is now the developer account; left {left} committee membership(s)."
        ))
