"""Who may do what, and who hears about it.

Roles:
- **Admin** (Member.is_admin or Django superuser): adds people and committees, changes roles.
- **Core committee** (member of the committee marked is_core): sees everything, assigns tasks to
  any committee or person, posts announcements to anyone, calls general or committee meetings.
- **Committee head**: the same powers inside the committees they head.
- **Member**: sees their committees' work, updates and comments on tasks, replies to meetings,
  reads and acknowledges announcements.
"""

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from .models import (
    Announcement,
    Attendee,
    Committee,
    Meeting,
    Member,
    Membership,
    Notification,
    Receipt,
    Task,
)

# ----------------------------------------------------------------------- roles


class Perms:
    """Roles of one member, worked out once per request."""

    def __init__(self, member):
        self.member = member
        rows = list(
            Membership.objects.filter(member=member, committee__archived=False).values_list(
                "committee_id", "role", "committee__is_core"
            )
        )
        self.committee_ids = {c for c, _, _ in rows}
        self.headed_ids = {c for c, r, _ in rows if r == Membership.HEAD}
        self.demo = member.is_demo
        self.admin = member.admin and not self.demo
        self.core = not self.demo and (self.admin or any(core for _, _, core in rows))

    # people & committees
    def can_manage_people(self):
        return self.admin or self.core

    def can_manage_committee(self, committee_id):
        return self.core or committee_id in self.headed_ids

    def can_lead(self):
        """Can create tasks / announcements / meetings at all."""
        return self.core or bool(self.headed_ids)

    def leadable_committee_ids(self):
        if self.core:
            return set(Committee.objects.filter(archived=False, is_demo=False).values_list("pk", flat=True))
        return set(self.headed_ids)

    def committees_visible(self, qs=None):
        qs = Committee.objects.filter(archived=False) if qs is None else qs
        return qs.filter(is_demo=self.demo)

    def people_visible(self, qs=None):
        """Developers are seen only by themselves; demo accounts and real members never see each other."""
        qs = Member.objects.all() if qs is None else qs
        qs = qs.filter(is_demo=self.demo)
        return qs if self.member.is_developer else qs.filter(is_developer=False)

    # tasks
    def tasks_visible(self, qs=None):
        qs = Task.objects.all() if qs is None else qs
        if self.core:
            return qs
        return qs.filter(
            Q(committee_id__in=self.committee_ids) | Q(assignees=self.member) | Q(created_by=self.member)
        ).distinct()

    def can_manage_task(self, task):
        """Edit, reassign, delete."""
        return self.core or task.created_by_id == self.member.pk or task.committee_id in self.headed_ids

    def can_work_on_task(self, task):
        """Change status, comment."""
        return (
            self.can_manage_task(task)
            or task.committee_id in self.committee_ids
            or task.assignees.filter(pk=self.member.pk).exists()
        )

    # announcements
    def announcements_visible(self, qs=None):
        qs = Announcement.objects.all() if qs is None else qs
        if self.core:
            return qs
        return qs.filter(Q(receipts__member=self.member) | Q(author=self.member)).distinct()

    def can_manage_announcement(self, a):
        return self.core or a.author_id == self.member.pk

    # meetings
    def meetings_visible(self, qs=None):
        qs = Meeting.objects.all() if qs is None else qs
        if self.core:
            return qs
        return qs.filter(
            Q(attendees__member=self.member) | Q(created_by=self.member) | Q(committee_id__in=self.headed_ids)
        ).distinct()

    def can_manage_meeting(self, m):
        return self.core or m.created_by_id == self.member.pk or (m.committee_id in self.headed_ids)


def active_members():
    """Real members: active, and not the hidden developer account."""
    return Member.objects.filter(user__is_active=True, is_developer=False, is_demo=False)


# ----------------------------------------------------------------------- audiences


def announcement_recipients(a):
    if a.audience == Announcement.ALL:
        qs = active_members()
    elif a.audience == Announcement.COMMITTEES:
        qs = active_members().filter(memberships__committee__in=a.committees.all())
    else:
        qs = active_members().filter(pk__in=a.people.values("pk"))
    return list(qs.distinct())


def meeting_invitees(m):
    qs = active_members()
    if m.committee_id:
        qs = qs.filter(memberships__committee_id=m.committee_id)
    return list(qs.distinct())


@transaction.atomic
def publish_announcement(a, actor):
    people = announcement_recipients(a)
    Receipt.objects.bulk_create(
        [Receipt(announcement=a, member=p, read_at=timezone.now() if p.pk == actor.pk else None) for p in people],
        ignore_conflicts=True,
    )
    tag = "Urgent: " if a.urgent else ""
    notify(
        [p for p in people if p.pk != actor.pk],
        "announcement", a.pk, f"{tag}{a.title}", _snippet(a.body), urgent=a.urgent,
    )
    return len(people)


@transaction.atomic
def invite_to_meeting(m, actor, notify_title=None):
    """Adds everyone in the meeting's audience who isn't invited yet. Returns the new invitees."""
    have = set(m.attendees.values_list("member_id", flat=True))
    new = [p for p in meeting_invitees(m) if p.pk not in have]
    Attendee.objects.bulk_create(
        [Attendee(meeting=m, member=p, rsvp=Attendee.GOING if p.pk == actor.pk else Attendee.PENDING) for p in new],
        ignore_conflicts=True,
    )
    when = timezone.localtime(m.start).strftime("%a %-d %b, %H:%M")
    notify([p for p in new if p.pk != actor.pk], "meeting", m.pk, notify_title or f"Meeting: {m.title}", when)
    return new


def task_watchers(task, exclude=None):
    """Assignees and creator; if nobody is assigned, the committee's heads."""
    people = set(task.assignees.filter(user__is_active=True))
    if not people:
        people = set(
            active_members().filter(memberships__committee=task.committee, memberships__role=Membership.HEAD)
        )
    if task.created_by_id and task.created_by.active:
        people.add(task.created_by)
    if exclude is not None:
        people.discard(exclude)
    return list(people)


def task_new_audience(task, actor):
    """Who hears about a new task: assignees, or the whole committee when nobody is assigned."""
    if task.assignees.exists():
        people = list(task.assignees.filter(user__is_active=True))
    else:
        people = list(active_members().filter(memberships__committee=task.committee).distinct())
    return [p for p in people if p.pk != actor.pk]


# ----------------------------------------------------------------------- notifications


def _snippet(text, n=140):
    text = " ".join((text or "").split())
    return text if len(text) <= n else text[: n - 1] + "…"


def notify(members, kind, object_id, title, body="", urgent=False):
    members = [m for m in members if m is not None]
    if not members:
        return
    Notification.objects.bulk_create(
        [Notification(member=m, kind=kind, object_id=object_id, title=title[:200], body=_snippet(body, 300))
         for m in members]
    )
    from . import push

    ids = [m.pk for m in members]
    transaction.on_commit(lambda: push.send_async(ids, kind, object_id, title, _snippet(body), urgent))
