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
    is_admin = models.BooleanField(
        "App admin", default=False, help_text="Can add people, committees and change roles."
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
    def admin(self):
        return self.is_admin or self.user.is_superuser


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
