"""Who may do what, and who hears about it.

Levels:
- **Developer** (hidden owner account) and **Super admin**: everything, including appointing
  admins and super admins.
- **Admin**: everything except appointing or changing admins / super admins.
- **Member**: sees their wings' work, updates tasks, ticks off responsibilities, replies to
  meetings, reads announcements, plus any individual **permissions** (Grant) an admin gave them,
  each for their own wings or for all wings.
Positions (Chairman, Convenor, …) and member type (Executive / Member) are labels only.
"""

from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from .models import (
    Announcement,
    Attendee,
    Committee,
    Grant,
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
        self.committee_ids = set(
            Membership.objects.filter(member=member, committee__archived=False).values_list("committee_id", flat=True)
        )
        self.grants = dict(Grant.objects.filter(member=member).values_list("perm", "all_wings"))
        self.demo = member.is_demo
        self.public = member.is_public
        self.super = member.super and not self.demo and not self.public
        self.admin = member.admin and not self.demo and not self.public
        self.core = self.admin  # sees and may do everything with the members' content

    def _all_wing_ids(self):
        return set(Committee.objects.filter(archived=False, is_demo=self.demo).values_list("pk", flat=True))

    def has(self, perm):
        return self.admin or perm in self.grants

    def all_wings(self, perm):
        return self.admin or self.grants.get(perm) is True

    def wings_for(self, perm):
        """Wing ids where this person may use a permission."""
        if self.all_wings(perm):
            return self._all_wing_ids()
        if perm in self.grants:
            return set(self.committee_ids)
        return set()

    @property
    def headed_ids(self):
        """Wings where this person can lead (create work) at all."""
        ids = set()
        for p in (Grant.TASKS, Grant.ANNOUNCEMENTS, Grant.MEETINGS, Grant.RESPONSIBILITIES):
            ids |= self.wings_for(p)
        return ids

    def permissions(self):
        """{perm: "all" | "own"} for the app."""
        if self.admin:
            return {p: "all" for p, _ in Grant.PERMS}
        return {p: ("all" if a else "own") for p, a in self.grants.items()}

    # people & wings
    def can_manage_people(self):
        return self.has(Grant.PEOPLE)

    def can_manage_committee(self, committee_id):
        return committee_id in self.wings_for(Grant.PEOPLE)

    def can_set_level(self, target=None):
        """Only super admins (and the developer) appoint or change admins and super admins."""
        return self.super

    def can_lead(self, perm=None):
        if perm:
            return bool(self.wings_for(perm)) or (perm == Grant.PUBLIC and self.has(perm))
        return bool(self.headed_ids)

    def leadable_committee_ids(self, perm=None):
        return self.wings_for(perm) if perm else self.headed_ids

    def committees_visible(self, qs=None):
        qs = Committee.objects.filter(archived=False) if qs is None else qs
        if self.public:
            return qs.none()  # public users see wings only through the public Who's who
        return qs.filter(is_demo=self.demo)

    def people_visible(self, qs=None):
        """Developers are seen only by themselves; demo accounts, public users and members are kept apart."""
        qs = Member.objects.all() if qs is None else qs
        if self.public:
            return qs.filter(pk=self.member.pk)  # only themselves
        qs = qs.filter(is_demo=self.demo, is_public=False)
        return qs if self.member.is_developer else qs.filter(is_developer=False)

    # tasks
    def tasks_visible(self, qs=None):
        qs = Task.objects.all() if qs is None else qs
        if self.all_wings(Grant.TASKS):
            return qs.filter(committee__is_demo=self.demo)
        return qs.filter(
            Q(committee_id__in=self.committee_ids | self.wings_for(Grant.TASKS))
            | Q(assignees=self.member) | Q(created_by=self.member)
        ).distinct()

    def can_manage_task(self, task):
        """Edit, reassign, delete."""
        return task.created_by_id == self.member.pk or task.committee_id in self.wings_for(Grant.TASKS)

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
        if self.admin:
            return qs
        return qs.filter(Q(receipts__member=self.member) | Q(author=self.member)).distinct()

    def can_manage_announcement(self, a):
        return self.admin or a.author_id == self.member.pk

    # meetings
    def meetings_visible(self, qs=None):
        qs = Meeting.objects.all() if qs is None else qs
        if self.admin:
            return qs
        return qs.filter(
            Q(attendees__member=self.member) | Q(created_by=self.member)
            | Q(committee_id__in=self.wings_for(Grant.MEETINGS))
        ).distinct()

    def can_manage_meeting(self, m):
        return self.admin or m.created_by_id == self.member.pk or m.committee_id in self.wings_for(Grant.MEETINGS)

    # responsibilities
    def responsibilities_visible(self, qs=None):
        from .models import Responsibility

        qs = Responsibility.objects.all() if qs is None else qs
        if self.all_wings(Grant.RESPONSIBILITIES):
            return qs.filter(holder__is_demo=self.demo)
        return qs.filter(
            Q(holder=self.member) | Q(committee_id__in=self.committee_ids | self.wings_for(Grant.RESPONSIBILITIES))
            | Q(created_by=self.member)
        ).distinct()

    def can_manage_responsibility(self, r):
        return (r.created_by_id == self.member.pk
                or (r.committee_id in self.wings_for(Grant.RESPONSIBILITIES))
                or self.all_wings(Grant.RESPONSIBILITIES))


def active_members():
    """Real members: active, not the hidden developer account, not demo or public users."""
    return Member.objects.filter(user__is_active=True, is_developer=False, is_demo=False, is_public=False)


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
    """Assignees and creator; if nobody is assigned, the whole wing."""
    people = set(task.assignees.filter(user__is_active=True))
    if not people:
        people = set(active_members().filter(memberships__committee=task.committee))
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


def notify(members, kind, object_id, title, body="", urgent=False, push_each=True):
    members = [m for m in members if m is not None]
    if not members:
        return
    Notification.objects.bulk_create(
        [Notification(member=m, kind=kind, object_id=object_id, title=title[:200], body=_snippet(body, 300))
         for m in members]
    )
    if not push_each:
        return
    from . import push

    ids = [m.pk for m in members]
    transaction.on_commit(lambda: push.send_async(ids, kind, object_id, title, _snippet(body), urgent))
