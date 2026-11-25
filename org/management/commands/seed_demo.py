"""Example data for trying the app locally. Refuses to run unless DEBUG is on (or --force).

Every demo account's password is the one printed at the end.
"""

from datetime import timedelta

from django.conf import settings
from django.contrib.auth.models import User
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.utils import timezone

from org.models import Announcement, Committee, Meeting, Member, Membership, Task, TaskUpdate
from org.services import invite_to_meeting, publish_announcement

PASSWORD = "demo-pass-2026"

COMMITTEES = [
    ("Core Committee", "teal", True, "Runs the unit, assigns work and speaks for everyone."),
    ("Education", "indigo", False, "Classes, study circles and the youth program."),
    ("Welfare", "green", False, "Support for members and families in need."),
    ("Media & IT", "purple", False, "Posters, social media, photos and the website."),
    ("Finance", "amber", False, "Collections, budgets and accounts."),
    ("Events", "orange", False, "Venues, logistics and hospitality."),
    ("Sports", "red", False, "Tournaments and weekend games."),
]

PEOPLE = [
    # name, email, phone, title, [(committee, role)]
    ("Abdul Rahman", "admin@example.org", "+966 50 000 0001", "President", [("Core Committee", "head")]),
    ("Mohammed Irfan", "irfan@example.org", "+966 50 000 0002", "General Secretary", [("Core Committee", "member")]),
    ("Sameer Ahmed", "sameer@example.org", "+966 50 000 0003", "Treasurer", [("Core Committee", "member"), ("Finance", "head")]),
    ("Faisal Khan", "faisal@example.org", "+966 50 000 0004", "", [("Education", "head")]),
    ("Imran Shaikh", "imran@example.org", "+966 50 000 0005", "", [("Education", "member"), ("Sports", "member")]),
    ("Yusuf Pasha", "yusuf@example.org", "+966 50 000 0006", "", [("Welfare", "head")]),
    ("Zaid Hussain", "zaid@example.org", "+966 50 000 0007", "", [("Welfare", "member")]),
    ("Nawaz Sharief", "nawaz@example.org", "+966 50 000 0008", "", [("Media & IT", "head")]),
    ("Asif Ali", "asif@example.org", "+966 50 000 0009", "", [("Media & IT", "member"), ("Events", "member")]),
    ("Tanveer Ahmed", "tanveer@example.org", "+966 50 000 0010", "", [("Finance", "member")]),
    ("Riyaz Basha", "riyaz@example.org", "+966 50 000 0011", "", [("Events", "head")]),
    ("Arif Mulla", "arif@example.org", "+966 50 000 0012", "", [("Events", "member")]),
    ("Junaid Kazi", "junaid@example.org", "+966 50 000 0013", "", [("Sports", "head")]),
    ("Kaleem Ulla", "kaleem@example.org", "+966 50 000 0014", "", [("Sports", "member"), ("Welfare", "member")]),
]


class Command(BaseCommand):
    help = "Load example committees, people, tasks, announcements and meetings."

    def add_arguments(self, parser):
        parser.add_argument("--force", action="store_true")

    @transaction.atomic
    def handle(self, *args, **o):
        if not settings.DEBUG and not o["force"]:
            raise CommandError("Demo data is for local use. Run with DEBUG=1 (or --force).")
        if Committee.objects.exists():
            raise CommandError("The database already has committees.")
        now = timezone.now()
        today = timezone.localdate()
        c = {}
        for i, (name, color, core, desc) in enumerate(COMMITTEES):
            c[name] = Committee.objects.create(name=name, color=color, is_core=core, description=desc, order=i)
        m = {}
        for name, email, phone, title, roles in PEOPLE:
            u = User.objects.create_user(username=email, email=email, password=PASSWORD, first_name=name)
            mem = u.member
            mem.name, mem.phone, mem.title = name, phone, title
            mem.level = "super" if email.startswith("admin") else ""
            mem.save()
            for cname, role in roles:
                Membership.objects.create(member=mem, committee=c[cname], role=role)
            m[name.split()[0]] = mem
        boss = m["Abdul"]

        def task(title, committee, who, days, pri=2, status="todo", by=boss, desc=""):
            t = Task.objects.create(title=title, committee=c[committee], created_by=by, priority=pri, status=status,
                                    due_date=today + timedelta(days=days) if days is not None else None,
                                    description=desc)
            t.assignees.set([m[w] for w in who])
            TaskUpdate.objects.create(task=t, author=by, kind="created",
                                      to_value=f"{committee} · " + ", ".join(m[w].name for w in who) if who else committee,
                                      created_at=now - timedelta(days=3))
            return t

        t = task("Book the hall for the annual gathering", "Events", ["Riyaz"], 5, 3,
                 "doing", desc="Capacity ~300. Get two quotes, prefer the Olaya side.")
        TaskUpdate.objects.create(task=t, author=m["Riyaz"], kind="status", from_value="To do", to_value="In progress",
                                  body="Visited two halls, waiting for prices.", created_at=now - timedelta(days=1))
        task("Design the poster for the gathering", "Media & IT", ["Nawaz", "Asif"], 3, 3)
        task("Collect monthly contributions", "Finance", ["Tanveer"], -2, 4,
             desc="Follow up with members who haven't paid for October and November.")
        task("Prepare the weekend study circle schedule", "Education", ["Faisal"], 7)
        task("Visit the family in Al Malaz", "Welfare", ["Yusuf", "Zaid"], 1, 4, "doing")
        task("Cricket tournament: register teams", "Sports", ["Junaid"], 10)
        task("Update the members list", "Core Committee", ["Mohammed"], 4)
        task("Audit last quarter's accounts", "Finance", ["Sameer"], None, 2, "done")
        task("Youth quiz questions", "Education", [], 14, 2, by=m["Faisal"])

        def announce(title, body, author, audience="all", committees=(), **kw):
            a = Announcement.objects.create(title=title, body=body, author=author, audience=audience,
                                            posted_as=c["Core Committee"] if audience == "all" else c[committees[0]], **kw)
            a.committees.set([c[x] for x in committees])
            publish_announcement(a, author)
            return a

        announce("Annual gathering on 12 December",
                 "All members and families are invited to the annual gathering, in shaa Allah. Venue and timings "
                 "will follow. Please confirm how many people from your family will come.", boss, pinned=True,
                 requires_ack=True)
        announce("Monthly contribution reminder",
                 "Please clear your monthly contribution before the 5th. Contact Tanveer for any questions.",
                 m["Sameer"], "committees", ["Finance"])
        announce("New study circle for youth",
                 "A new Saturday study circle for ages 14–20 starts next week after Maghrib.", m["Faisal"],
                 "committees", ["Education"])

        def meeting(title, committee, days, hour, place, by=boss, agenda=""):
            start = timezone.make_aware(timezone.datetime.combine(today + timedelta(days=days), timezone.datetime.min.time())
                                        .replace(hour=hour))
            mt = Meeting.objects.create(title=title, committee=c[committee] if committee else None, start=start,
                                        end=start + timedelta(hours=1, minutes=30), location=place, created_by=by,
                                        agenda=agenda)
            invite_to_meeting(mt, by)
            return mt

        meeting("Core committee weekly", "Core Committee", 2, 21, "President's home, Al Olaya",
                agenda="1. Annual gathering\n2. Contributions\n3. New members")
        meeting("General body meeting", None, 9, 20, "Community hall", agenda="Yearly report and elections")
        meeting("Events planning", "Events", 1, 21, "Online", by=m["Riyaz"])
        past = meeting("Media team sync", "Media & IT", -6, 21, "Online", by=m["Nawaz"])
        past.minutes = "Poster drafts reviewed. Asif to finish the final design by Thursday."
        past.minutes_by = m["Nawaz"]
        past.minutes_at = now - timedelta(days=5)
        past.save()

        self.stdout.write(self.style.SUCCESS(
            f"Demo data loaded: {len(c)} committees, {len(m)} people. Log in as admin@example.org "
            f"(or +966 50 000 0001) with password {PASSWORD}"
        ))
