"""First-time setup: creates the core committee and the first admin, and prints an invite code.

    python manage.py setup_org --name "Hisham" --email you@example.com [--phone +9665...]
"""

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from org.models import Committee, Invite, Member, Membership, phone_digits


class Command(BaseCommand):
    help = "Create the core committee and the first admin (prints an invite code to set the password in the app)."

    def add_arguments(self, parser):
        parser.add_argument("--name", required=True)
        parser.add_argument("--email", default="")
        parser.add_argument("--phone", default="")
        parser.add_argument("--core", default="Core Committee", help="Name of the core committee.")

    @transaction.atomic
    def handle(self, *args, **o):
        if not o["email"] and not o["phone"]:
            raise CommandError("Give --email or --phone.")
        core, _ = Committee.objects.get_or_create(
            is_core=True, archived=False, defaults={"name": o["core"], "color": "teal", "order": 0}
        )
        email = o["email"].strip().lower()
        user = User.objects.filter(email__iexact=email).first() if email else None
        if user is None:
            user = User(username=email or f"p{phone_digits(o['phone'])}", email=email, first_name=o["name"][:150])
            user.set_unusable_password()
            user.save()
        member, _ = Member.objects.get_or_create(user=user, defaults={"name": o["name"]})
        member.name = o["name"]
        member.phone = o["phone"] or member.phone
        member.is_admin = True
        member.save()
        Membership.objects.update_or_create(member=member, committee=core, defaults={"role": Membership.HEAD})
        code = Invite.issue(member)
        self.stdout.write(self.style.SUCCESS(f"Admin: {member.name} · core committee: {core.name}"))
        self.stdout.write(f"In the app, tap “I have an invite code” and enter:  {code}")
