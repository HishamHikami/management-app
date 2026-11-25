"""Demo login for App Store / Google Play reviewers.

Creates a hidden "Demo Committee" with sample people, tasks, an announcement and a meeting, and
a reviewer account that heads it. Demo accounts and real members can never see each other.

    deploy/manage.sh setup_review_demo            # create (prints the login)
    deploy/manage.sh setup_review_demo --reset    # new password for the reviewer
"""

import secrets
from datetime import timedelta

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand
from django.db import transaction
from django.utils import timezone

from org.models import Announcement, Attendee, Committee, Grant, Meeting, Membership, Receipt, Task, TaskUpdate

LOGIN = "review@ksa-riyadh.halacreative.com"
PEOPLE = [("Ahmed (demo)", "Secretary"), ("Bilal (demo)", ""), ("Zakir (demo)", ""), ("Imran (demo)", "")]


def _password():
    return "-".join(secrets.token_hex(3) for _ in range(3))


class Command(BaseCommand):
    help = "Create the hidden demo committee and reviewer login for app-store review."

    def add_arguments(self, parser):
        parser.add_argument("--reset", action="store_true", help="Give the reviewer a new password.")

    @transaction.atomic
    def handle(self, *args, **o):
        existing = User.objects.filter(username=LOGIN).first()
        if existing:
            if not o["reset"]:
                self.stdout.write("The demo already exists. Use --reset for a new reviewer password.")
                return
            pw = _password()
            existing.set_password(pw)
            existing.is_active = True
            existing.save()
            self.stdout.write(self.style.SUCCESS(f"Reviewer login: {LOGIN}  password: {pw}"))
            return

        now, today = timezone.now(), timezone.localdate()
        c = Committee.objects.create(name="Demo Committee", is_demo=True, color="blue",
                                     description="Sample committee for app review. Not real data.")

        def person(name, title="", login=None, pw=None):
            u = User(username=login or f"demo-{secrets.token_hex(4)}", email=login or "", first_name=name[:150])
            u.set_password(pw) if pw else u.set_unusable_password()
            u.save()
            m = u.member
            m.name, m.title, m.is_demo = name, title, True
            m.save()
            return m

        pw = _password()
        reviewer = person("App Reviewer", "Committee head", LOGIN, pw)
        Membership.objects.create(member=reviewer, committee=c, position="Chairman")
        for perm in (Grant.TASKS, Grant.RESPONSIBILITIES, Grant.ANNOUNCEMENTS, Grant.MEETINGS, Grant.PEOPLE):
            Grant.objects.create(member=reviewer, perm=perm)
        others = [person(n, t) for n, t in PEOPLE]
        for m in others:
            Membership.objects.create(member=m, committee=c)
        everyone = [reviewer, *others]

        def task(title, who, days, status="todo", pri=2):
            t = Task.objects.create(title=title, committee=c, created_by=reviewer, status=status, priority=pri,
                                    due_date=today + timedelta(days=days))
            t.assignees.set(who)
            TaskUpdate.objects.create(task=t, author=reviewer, kind="created", to_value=c.name)
            return t

        task("Book a hall for the monthly gathering", [others[0]], 3, "doing", 3)
        task("Prepare the attendance sheet", [reviewer], 1)
        task("Share the poster with members", [others[1], others[2]], 6)
        t = task("Collect feedback from last event", [others[3]], -1, "done")
        TaskUpdate.objects.create(task=t, author=others[3], kind="comment", body="Done, 12 responses collected.")

        a = Announcement.objects.create(
            title="Monthly gathering this Friday", author=reviewer, posted_as=c, audience=Announcement.COMMITTEES,
            body="Assalamu alaikum. The monthly gathering is on Friday after Isha. Please confirm you have read this.",
            requires_ack=True)
        a.committees.set([c])
        Receipt.objects.bulk_create([Receipt(announcement=a, member=m, read_at=now if m == reviewer else None)
                                     for m in everyone])

        start = (now + timedelta(days=2)).replace(hour=18, minute=0, second=0, microsecond=0)
        mt = Meeting.objects.create(title="Demo committee meeting", committee=c, start=start,
                                    end=start + timedelta(hours=1), location="Community hall",
                                    agenda="1. Monthly gathering\n2. Next event", created_by=reviewer)
        Attendee.objects.bulk_create([Attendee(meeting=mt, member=m, rsvp="going" if m == reviewer else "pending")
                                      for m in everyone])
        self.stdout.write(self.style.SUCCESS(f"Reviewer login: {LOGIN}  password: {pw}"))
