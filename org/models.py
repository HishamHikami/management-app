"""Data model: members, committees, tasks, announcements, meetings, notifications."""

import hashlib
import re
import secrets
from datetime import timedelta

from django.conf import settings
from django.contrib.auth.models import User
from django.db import models
from django.utils import timezone

COLORS = [
    ("teal", "Teal"),
    ("blue", "Blue"),
    ("indigo", "Indigo"),
    ("purple", "Purple"),
    ("pink", "Pink"),
    ("red", "Red"),
    ("orange", "Orange"),
    ("amber", "Amber"),
    ("green", "Green"),
    ("gray", "Gray"),
]


def phone_digits(phone):
    """A comparable key for a phone number: digits only, so that +966 50…, 00966 50…
    and 050… all give the same key."""
    d = re.sub(r"\D", "", phone or "")
    if d.startswith("00"):
        d = d[2:]
    if d.startswith("966") and len(d) > 9:
        d = d[3:]
    return d.lstrip("0")


# ----------------------------------------------------------------------- people


class Member(models.Model):
    """A person in the organization. Every login has exactly one Member."""

    user = models.OneToOneField(User, on_delete=models.CASCADE, related_name="member")
    name = models.CharField(max_length=120)
    phone = models.CharField(max_length=30, blank=True)
    phone_key = models.CharField(max_length=30, blank=True, db_index=True, editable=False)
    title = models.CharField("Position / title", max_length=80, blank=True)
    EXECUTIVE, MEMBER = "executive", "member"
    TYPES = [(EXECUTIVE, "Executive"), (MEMBER, "Member")]
    SUPER, ADMIN = "super", "admin"
    LEVELS = [("", "Member"), (ADMIN, "Admin"), (SUPER, "Super admin")]

    member_type = models.CharField(max_length=10, choices=TYPES, default=MEMBER)
    unit_place = models.CharField("Unit place", max_length=60, blank=True)
    level = models.CharField(
        max_length=5, choices=LEVELS, default="", blank=True,
        help_text="Super admins manage everything incl. admins; admins manage everything else.",
    )
    notes = models.TextField("Private notes", blank=True, help_text="Only admins see these.")
    needs_followup = models.BooleanField(default=False)
    is_public = models.BooleanField(
        "Public user", default=False, help_text="Registered from the public side; not a member."
    )
    is_demo = models.BooleanField(
        "Store-review demo", default=False,
        help_text="Lives in the demo committee only; can't see real people or work.",
    )
    is_developer = models.BooleanField(
        "Developer account", default=False,
        help_text="Full access, hidden from the people list, announcements, meetings and stats.",
    )
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["name"]

    def __str__(self):
        return self.name

    def save(self, *args, **kwargs):
        self.phone_key = phone_digits(self.phone)
        super().save(*args, **kwargs)

    @property
    def email(self):
        return self.user.email

    @property
    def active(self):
        return self.user.is_active

    @property
    def is_admin(self):
        return self.level in (self.ADMIN, self.SUPER)

    @property
    def super(self):
        return self.level == self.SUPER or self.is_developer or self.user.is_superuser

    @property
    def admin(self):
        return self.super or self.level == self.ADMIN


class Committee(models.Model):
    """A committee. Exactly one should be the core committee, which runs the organization."""

    name = models.CharField(max_length=80, unique=True)
    description = models.TextField(blank=True)
    color = models.CharField(max_length=10, choices=COLORS, default="teal")
    is_core = models.BooleanField(
        "Core committee", default=False, help_text="Its members can assign work and post to everyone."
    )
    order = models.PositiveIntegerField(default=0)
    archived = models.BooleanField(default=False)
    is_demo = models.BooleanField(default=False, help_text="Sample committee for app-store reviewers; hidden from members.")
    created_at = models.DateTimeField(auto_now_add=True)
    members = models.ManyToManyField(Member, through="Membership", related_name="committees")

    class Meta:
        ordering = ["-is_core", "order", "name"]

    def __str__(self):
        return self.name


class Membership(models.Model):
    HEAD = "head"
    MEMBER = "member"
    ROLES = [(HEAD, "Head"), (MEMBER, "Member")]

    member = models.ForeignKey(Member, on_delete=models.CASCADE, related_name="memberships")
    committee = models.ForeignKey(Committee, on_delete=models.CASCADE, related_name="memberships")
    role = models.CharField(max_length=10, choices=ROLES, default=MEMBER)
    position = models.CharField(
        max_length=60, blank=True, help_text="Optional, e.g. Secretary, Treasurer, Coordinator."
    )
    joined_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["member", "committee"], name="one_membership")]
        ordering = ["role", "member__name"]  # heads first ("head" < "member")

    def __str__(self):
        return f"{self.member} · {self.committee} ({self.role})"


class Invite(models.Model):
    """A one-time code a new member uses to set their password."""

    member = models.ForeignKey(Member, on_delete=models.CASCADE, related_name="invites")
    code_hash = models.CharField(max_length=64, unique=True)
    created_by = models.ForeignKey(Member, on_delete=models.SET_NULL, null=True, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    used_at = models.DateTimeField(null=True, blank=True)

    ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"  # no 0/O, 1/I

    @staticmethod
    def hash(code):
        clean = re.sub(r"[^A-Z0-9]", "", (code or "").upper())
        return hashlib.sha256(clean.encode()).hexdigest()

    @classmethod
    def issue(cls, member, by=None):
        cls.objects.filter(member=member, used_at__isnull=True).delete()
        raw = "".join(secrets.choice(cls.ALPHABET) for _ in range(8))
        cls.objects.create(
            member=member,
            code_hash=cls.hash(raw),
            created_by=by,
            expires_at=timezone.now() + timedelta(days=settings.INVITE_DAYS),
        )
        return f"{raw[:4]}-{raw[4:]}"

    @classmethod
    def find(cls, code):
        return (
            cls.objects.select_related("member__user")
            .filter(code_hash=cls.hash(code), used_at__isnull=True, expires_at__gt=timezone.now())
            .first()
        )


class ApiToken(models.Model):
    """A login for the phone app. Only a SHA-256 hash of the token is stored."""

    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name="api_tokens")
    key_hash = models.CharField(max_length=64, unique=True)
    device = models.CharField(max_length=100, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    last_used_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]

    def __str__(self):
        return f"{self.user} · {self.device or 'app'}"

    @staticmethod
    def hash(raw):
        return hashlib.sha256(raw.encode()).hexdigest()

    @classmethod
    def issue(cls, user, device=""):
        raw = "om_" + secrets.token_urlsafe(32)
        cls.objects.create(user=user, key_hash=cls.hash(raw), device=device[:100])
        return raw


class Device(models.Model):
    """A phone that receives push notifications (Firebase registration token)."""

    member = models.ForeignKey(Member, on_delete=models.CASCADE, related_name="devices")
    token = models.CharField(max_length=300, unique=True)
    api_token = models.ForeignKey(ApiToken, on_delete=models.CASCADE, null=True, blank=True, related_name="push_devices")
    updated_at = models.DateTimeField(auto_now=True)


# ----------------------------------------------------------------------- tasks


class Task(models.Model):
    TODO, DOING, WAITING, DONE, CANCELLED = "todo", "doing", "waiting", "done", "cancelled"
    STATUSES = [
        (TODO, "To do"),
        (DOING, "In progress"),
        (WAITING, "Waiting"),
        (DONE, "Done"),
        (CANCELLED, "Cancelled"),
    ]
    CLOSED = {DONE, CANCELLED}
    PRIORITIES = [(1, "Low"), (2, "Normal"), (3, "High"), (4, "Urgent")]

    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    committee = models.ForeignKey(
        Committee, on_delete=models.PROTECT, related_name="tasks", help_text="The committee responsible."
    )
    assignees = models.ManyToManyField(Member, blank=True, related_name="assigned_tasks")
    created_by = models.ForeignKey(Member, on_delete=models.SET_NULL, null=True, related_name="created_tasks")
    status = models.CharField(max_length=10, choices=STATUSES, default=TODO)
    priority = models.PositiveSmallIntegerField(choices=PRIORITIES, default=2)
    due_date = models.DateField(null=True, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    closed_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-priority", "due_date", "-created_at"]
        indexes = [models.Index(fields=["status", "due_date"])]

    def __str__(self):
        return self.title

    @property
    def is_closed(self):
        return self.status in self.CLOSED

    @property
    def is_overdue(self):
        return bool(self.due_date and not self.is_closed and self.due_date < timezone.localdate())


class TaskUpdate(models.Model):
    """One entry in a task's timeline."""

    CREATED, COMMENT, STATUS, ASSIGN, EDIT = "created", "comment", "status", "assign", "edit"
    KINDS = [(CREATED, "Created"), (COMMENT, "Comment"), (STATUS, "Status"), (ASSIGN, "Reassigned"), (EDIT, "Edited")]

    task = models.ForeignKey(Task, on_delete=models.CASCADE, related_name="updates")
    author = models.ForeignKey(Member, on_delete=models.SET_NULL, null=True, related_name="+")
    kind = models.CharField(max_length=10, choices=KINDS, default=COMMENT)
    body = models.TextField(blank=True)
    from_value = models.CharField(max_length=200, blank=True)
    to_value = models.CharField(max_length=200, blank=True)
    created_at = models.DateTimeField(default=timezone.now)

    class Meta:
        ordering = ["created_at", "pk"]


# ----------------------------------------------------------------------- announcements


class Announcement(models.Model):
    ALL, COMMITTEES, PEOPLE = "all", "committees", "people"
    AUDIENCES = [(ALL, "Everyone"), (COMMITTEES, "Selected committees"), (PEOPLE, "Selected people")]

    title = models.CharField(max_length=200)
    body = models.TextField()
    author = models.ForeignKey(Member, on_delete=models.SET_NULL, null=True, related_name="announcements")
    posted_as = models.ForeignKey(
        Committee, on_delete=models.SET_NULL, null=True, blank=True, related_name="+",
        help_text="The committee this is posted on behalf of.",
    )
    audience = models.CharField(max_length=12, choices=AUDIENCES, default=ALL)
    committees = models.ManyToManyField(Committee, blank=True, related_name="announcements")
    people = models.ManyToManyField(Member, blank=True, related_name="direct_announcements")
    pinned = models.BooleanField(default=False)
    urgent = models.BooleanField(default=False)
    requires_ack = models.BooleanField("Ask people to acknowledge", default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    edited_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-pinned", "-created_at"]

    def __str__(self):
        return self.title


class Receipt(models.Model):
    """Who an announcement was sent to, and whether they read / acknowledged it."""

    announcement = models.ForeignKey(Announcement, on_delete=models.CASCADE, related_name="receipts")
    member = models.ForeignKey(Member, on_delete=models.CASCADE, related_name="receipts")
    read_at = models.DateTimeField(null=True, blank=True)
    acked_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["announcement", "member"], name="one_receipt")]


# ----------------------------------------------------------------------- meetings


class Meeting(models.Model):
    SCHEDULED, CANCELLED = "scheduled", "cancelled"
    STATUSES = [(SCHEDULED, "Scheduled"), (CANCELLED, "Cancelled")]

    title = models.CharField(max_length=200)
    agenda = models.TextField(blank=True)
    committee = models.ForeignKey(
        Committee, on_delete=models.CASCADE, null=True, blank=True, related_name="meetings",
        help_text="Empty = general meeting for every member.",
    )
    start = models.DateTimeField()
    end = models.DateTimeField(null=True, blank=True)
    location = models.CharField(max_length=200, blank=True)
    online_link = models.URLField(blank=True)
    status = models.CharField(max_length=10, choices=STATUSES, default=SCHEDULED)
    created_by = models.ForeignKey(Member, on_delete=models.SET_NULL, null=True, related_name="+")
    minutes = models.TextField(blank=True)
    minutes_by = models.ForeignKey(Member, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")
    minutes_at = models.DateTimeField(null=True, blank=True)
    reminded = models.BooleanField(default=False, editable=False)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["start"]

    def __str__(self):
        return self.title

    @property
    def finish(self):
        return self.end or (self.start + timedelta(hours=1))

    @property
    def is_past(self):
        return self.finish < timezone.now()


class Attendee(models.Model):
    PENDING, GOING, MAYBE, DECLINED = "pending", "going", "maybe", "declined"
    RSVPS = [(PENDING, "No reply"), (GOING, "Going"), (MAYBE, "Maybe"), (DECLINED, "Can't come")]
    UNKNOWN, PRESENT, ABSENT, EXCUSED = "", "present", "absent", "excused"
    ATTENDANCE = [(UNKNOWN, "Not marked"), (PRESENT, "Present"), (ABSENT, "Absent"), (EXCUSED, "Excused")]

    meeting = models.ForeignKey(Meeting, on_delete=models.CASCADE, related_name="attendees")
    member = models.ForeignKey(Member, on_delete=models.CASCADE, related_name="meeting_invites")
    rsvp = models.CharField(max_length=10, choices=RSVPS, default=PENDING)
    attendance = models.CharField(max_length=10, choices=ATTENDANCE, default=UNKNOWN, blank=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["meeting", "member"], name="one_attendee")]
        ordering = ["member__name"]


# ----------------------------------------------------------------------- inbox


class Notification(models.Model):
    """In-app inbox entry; also sent as a push notification when Firebase is set up."""

    member = models.ForeignKey(Member, on_delete=models.CASCADE, related_name="notifications")
    kind = models.CharField(max_length=20)  # task, announcement, meeting
    object_id = models.PositiveIntegerField(null=True)
    title = models.CharField(max_length=200)
    body = models.CharField(max_length=300, blank=True)
    created_at = models.DateTimeField(auto_now_add=True)
    read_at = models.DateTimeField(null=True, blank=True)

    class Meta:
        ordering = ["-created_at"]
        indexes = [models.Index(fields=["member", "read_at"])]


# ----------------------------------------------------------------------- permissions


class Grant(models.Model):
    """A permission given to one person, for their own wings or for all wings."""

    TASKS, RESPONSIBILITIES, ANNOUNCEMENTS, MEETINGS = "tasks", "responsibilities", "announcements", "meetings"
    PUBLIC, PEOPLE, RESETS = "public", "people", "password_resets"
    PERMS = [
        (TASKS, "Assign tasks"),
        (RESPONSIBILITIES, "Manage responsibilities"),
        (ANNOUNCEMENTS, "Post announcements"),
        (MEETINGS, "Call meetings"),
        (PUBLIC, "Publish public content"),
        (PEOPLE, "Manage wing members"),
        (RESETS, "Handle password resets"),
    ]
    WING_SCOPED = {TASKS, RESPONSIBILITIES, ANNOUNCEMENTS, MEETINGS, PEOPLE}

    member = models.ForeignKey(Member, on_delete=models.CASCADE, related_name="grants")
    perm = models.CharField(max_length=20, choices=PERMS)
    all_wings = models.BooleanField(default=False)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["member", "perm"], name="one_grant")]


# ----------------------------------------------------------------------- responsibilities


class Responsibility(models.Model):
    """A recurring duty. Its holder chooses how often it repeats and when to be reminded."""

    DAILY, WEEKLY, MONTHLY, ONCE = "daily", "weekly", "monthly", "once"
    REPEATS = [(DAILY, "Every day"), (WEEKLY, "Every week"), (MONTHLY, "Every month"), (ONCE, "Once")]
    NONE, SAME_DAY, DAY_BEFORE = "none", "same_day", "day_before"
    REMINDS = [(NONE, "No reminder"), (SAME_DAY, "Morning of the day"), (DAY_BEFORE, "The day before")]

    title = models.CharField(max_length=200)
    description = models.TextField(blank=True)
    committee = models.ForeignKey(Committee, on_delete=models.SET_NULL, null=True, blank=True,
                                  related_name="responsibilities")
    holder = models.ForeignKey(Member, on_delete=models.CASCADE, related_name="responsibilities")
    created_by = models.ForeignKey(Member, on_delete=models.SET_NULL, null=True, related_name="+")
    repeat = models.CharField(max_length=8, choices=REPEATS, default=WEEKLY)
    weekday = models.PositiveSmallIntegerField(null=True, blank=True, help_text="0 = Monday")
    monthday = models.PositiveSmallIntegerField(null=True, blank=True)
    start_date = models.DateField(default=timezone.localdate)
    remind = models.CharField(max_length=10, choices=REMINDS, default=SAME_DAY)
    active = models.BooleanField(default=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["title"]

    def __str__(self):
        return self.title

    def occurs_on(self, d):
        if d < self.start_date:
            return False
        if self.repeat == self.DAILY:
            return True
        if self.repeat == self.WEEKLY:
            return d.weekday() == (self.weekday if self.weekday is not None else self.start_date.weekday())
        if self.repeat == self.MONTHLY:
            import calendar

            want = self.monthday or self.start_date.day
            last = calendar.monthrange(d.year, d.month)[1]
            return d.day == min(want, last)
        return d == self.start_date

    def occurrences(self, start, end):
        d = max(start, self.start_date)
        while d <= end:
            if self.occurs_on(d):
                yield d
            d += timedelta(days=1)


class ResponsibilityDone(models.Model):
    responsibility = models.ForeignKey(Responsibility, on_delete=models.CASCADE, related_name="done")
    due_date = models.DateField()
    done_by = models.ForeignKey(Member, on_delete=models.SET_NULL, null=True, related_name="+")
    done_at = models.DateTimeField(auto_now_add=True)
    note = models.CharField(max_length=500, blank=True)

    class Meta:
        constraints = [models.UniqueConstraint(fields=["responsibility", "due_date"], name="one_done")]
        ordering = ["-due_date"]


# ----------------------------------------------------------------------- public side


class Program(models.Model):
    """A recurring public programme, e.g. QHLS (Quran, Hadith, Learning, School)."""

    name = models.CharField(max_length=120)
    short_name = models.CharField(max_length=20, blank=True)
    description = models.TextField(blank=True)
    schedule = models.CharField(max_length=200, blank=True, help_text="e.g. Every Friday after Isha")
    location = models.CharField(max_length=200, blank=True)
    registration_url = models.URLField(blank=True)
    active = models.BooleanField(default=True)
    order = models.PositiveIntegerField(default=0)

    class Meta:
        ordering = ["order", "name"]

    def __str__(self):
        return self.name


class ProgramResource(models.Model):
    program = models.ForeignKey(Program, on_delete=models.CASCADE, related_name="resources")
    title = models.CharField(max_length=200)
    url = models.URLField()
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-created_at"]


class PublicPost(models.Model):
    NEWS, EVENT, LIVE, VIDEO = "news", "event", "live", "video"
    KINDS = [(NEWS, "Announcement"), (EVENT, "Event"), (LIVE, "Live"), (VIDEO, "Video")]
    CATEGORIES = [("qhls", "QHLS"), ("event", "Events"), ("lecture", "Lectures"), ("other", "Other")]

    kind = models.CharField(max_length=6, choices=KINDS, default=NEWS)
    title = models.CharField(max_length=200)
    body = models.TextField(blank=True)
    starts_at = models.DateTimeField(null=True, blank=True)
    ends_at = models.DateTimeField(null=True, blank=True)
    location = models.CharField(max_length=200, blank=True)
    link = models.URLField(blank=True, help_text="YouTube / live stream / registration link")
    category = models.CharField(max_length=10, choices=CATEGORIES, blank=True)
    program = models.ForeignKey(Program, on_delete=models.SET_NULL, null=True, blank=True, related_name="posts")
    pinned = models.BooleanField(default=False)
    created_by = models.ForeignKey(Member, on_delete=models.SET_NULL, null=True, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        ordering = ["-pinned", "-created_at"]

    def __str__(self):
        return self.title

    @property
    def is_live(self):
        if self.kind != self.LIVE:
            return False
        now = timezone.now()
        start = self.starts_at or self.created_at
        end = self.ends_at or (start + timedelta(hours=3))
        return start <= now <= end


class PasswordResetRequest(models.Model):
    phone = models.CharField(max_length=30)
    member = models.ForeignKey(Member, on_delete=models.CASCADE, null=True, blank=True, related_name="+")
    created_at = models.DateTimeField(auto_now_add=True)
    handled_at = models.DateTimeField(null=True, blank=True)
    handled_by = models.ForeignKey(Member, on_delete=models.SET_NULL, null=True, blank=True, related_name="+")

    class Meta:
        ordering = ["handled_at", "-created_at"]
