"""JSON API for the phone app.

Auth: POST /api/v1/auth/login with an email or phone number + password returns a token; send it
as `Authorization: Bearer <token>` on every other call. Only a hash of the token is stored.
New members (and anyone who forgot their password) get a one-time invite code from an admin and
set their own password with /auth/invite/accept.
"""

import json
import re
from datetime import date, datetime, timedelta
from datetime import timezone as dt_timezone
from functools import wraps
from urllib.parse import urlencode

from django.conf import settings
from django.contrib.auth import authenticate
from django.contrib.auth.models import User
from django.contrib.auth.password_validation import validate_password
from django.core.cache import cache
from django.core.exceptions import ValidationError
from django.core.validators import URLValidator, validate_email
from django.db import transaction
from django.db.models import Count, Q
from django.http import Http404, JsonResponse
from django.utils import timezone
from django.views.decorators.csrf import csrf_exempt

from . import push
from .models import (
    COLORS,
    Announcement,
    ApiToken,
    Attendee,
    Committee,
    Device,
    Invite,
    Meeting,
    Member,
    Membership,
    Notification,
    Receipt,
    Task,
    TaskUpdate,
    phone_digits,
)
from .services import (
    Perms,
    invite_to_meeting,
    notify,
    publish_announcement,
    task_new_audience,
    task_watchers,
)

# ======================================================================= plumbing


class Bad(Exception):
    """Validation error: {field: [messages]}."""

    def __init__(self, errors):
        super().__init__("invalid")
        self.errors = errors if isinstance(errors, dict) else {"__all__": [str(errors)]}


class Denied(Exception):
    pass


def _error(message, status=400, errors=None):
    payload = {"error": message}
    if errors:
        payload["errors"] = errors
    return JsonResponse(payload, status=status)


def ok(data=None, status=200):
    return JsonResponse(data if data is not None else {"ok": True}, status=status)


def api_view(methods=("GET",), auth=True):
    """Token-authenticated JSON view. Sets request.data, request.member and request.perms."""

    def deco(fn):
        @csrf_exempt  # no cookies are used; requests carry a bearer token
        @wraps(fn)
        def wrapper(request, *args, **kwargs):
            if request.method not in methods:
                return _error("Method not allowed.", 405)
            if auth:
                header = request.headers.get("Authorization", "")
                raw = header[7:].strip() if header.lower().startswith("bearer ") else ""
                token = (
                    ApiToken.objects.select_related("user__member").filter(key_hash=ApiToken.hash(raw)).first()
                    if raw
                    else None
                )
                if not token or not token.user.is_active or not hasattr(token.user, "member"):
                    return _error("Please log in again.", 401)
                request.api_token = token
                request.member = token.user.member
                request.perms = Perms(request.member)
                now = timezone.now()
                if not token.last_used_at or now - token.last_used_at > timedelta(minutes=10):
                    ApiToken.objects.filter(pk=token.pk).update(last_used_at=now)
            request.data = {}
            if request.method in ("POST", "PATCH", "PUT"):
                try:
                    data = json.loads(request.body) if request.body else {}
                except (ValueError, UnicodeDecodeError):
                    data = None
                if not isinstance(data, dict):
                    return _error("Send a JSON object.")
                request.data = data
            try:
                return fn(request, *args, **kwargs)
            except Bad as e:
                first = next(iter(e.errors.values()))[0]
                return _error(first, 400, e.errors)
            except Denied as e:
                return _error(str(e) or "You don't have permission to do that.", 403)
            except Http404:
                return _error("Not found.", 404)

        return wrapper

    return deco


def _get(qs, pk):
    obj = qs.filter(pk=pk).first()
    if obj is None:
        raise Http404
    return obj


def _ip(request):
    return request.META.get("HTTP_X_REAL_IP") or request.META.get("REMOTE_ADDR", "unknown")


# ---- input helpers


def text(d, key, label, max_len, required=False):
    v = d.get(key, "")
    v = "" if v is None else str(v).strip()
    if required and not v:
        raise Bad({key: [f"{label} is required."]})
    if len(v) > max_len:
        raise Bad({key: [f"{label} is too long (max {max_len} characters)."]})
    return v


def flag(d, key, default=False):
    v = d.get(key, default)
    return v is True or (isinstance(v, str) and v.lower() in ("1", "true", "yes", "on"))


def choice(d, key, label, options, default=None):
    v = d.get(key, default)
    valid = [o[0] for o in options]
    if v not in valid:
        raise Bad({key: [f"Choose a valid {label.lower()}."]})
    return v


def date_value(d, key, label):
    v = d.get(key)
    if v in (None, ""):
        return None
    try:
        return date.fromisoformat(str(v)[:10])
    except ValueError:
        raise Bad({key: [f"{label}: use a valid date."]})


def datetime_value(d, key, label, required=False):
    v = d.get(key)
    if v in (None, ""):
        if required:
            raise Bad({key: [f"{label} is required."]})
        return None
    try:
        dt = datetime.fromisoformat(str(v))
    except ValueError:
        raise Bad({key: [f"{label}: use a valid date and time."]})
    if timezone.is_naive(dt):
        dt = timezone.make_aware(dt)
    return dt


def id_list(d, key):
    v = d.get(key) or []
    if not isinstance(v, list):
        raise Bad({key: ["Send a list."]})
    try:
        return [int(x) for x in v]
    except (TypeError, ValueError):
        raise Bad({key: ["Send a list of ids."]})


def _iso(d):
    return timezone.localtime(d).isoformat() if isinstance(d, datetime) else (d.isoformat() if d else None)


# ======================================================================= serializers


def committee_brief(c):
    if c is None:
        return None
    return {"id": c.pk, "name": c.name, "color": c.color, "is_core": c.is_core}


def member_brief(m):
    if m is None:
        return None
    return {"id": m.pk, "name": m.name, "title": m.title, "phone": m.phone, "email": m.user.email}


def member_json(m, with_contact=True):
    data = member_brief(m)
    data.update({
        "is_admin": m.admin,
        "is_developer": m.is_developer,
        "active": m.user.is_active,
        "has_password": m.user.has_usable_password(),
        "committees": [
            {**committee_brief(ms.committee), "role": ms.role, "position": ms.position}
            for ms in m.memberships.select_related("committee").filter(committee__archived=False)
        ],
    })
    if not with_contact:
        data.pop("phone")
        data.pop("email")
    return data


PRIORITY_TONE = {4: "red", 3: "amber"}


def task_pill(t):
    if t.is_closed:
        return {"label": t.get_status_display(), "tone": "green" if t.status == Task.DONE else "ghost"}
    if t.is_overdue:
        return {"label": f"Overdue · {t.due_date:%-d %b}", "tone": "red"}
    if t.due_date:
        days = (t.due_date - timezone.localdate()).days
        label = "Due today" if days == 0 else "Due tomorrow" if days == 1 else f"Due {t.due_date:%-d %b}"
        return {"label": label, "tone": "amber" if days <= 1 else "neutral"}
    return None


def task_json(t):
    return {
        "id": t.pk,
        "title": t.title,
        "status": t.status,
        "status_label": t.get_status_display(),
        "priority": t.priority,
        "priority_label": t.get_priority_display(),
        "due_date": _iso(t.due_date),
        "is_overdue": t.is_overdue,
        "is_closed": t.is_closed,
        "committee": committee_brief(t.committee),
        "assignees": [member_brief(a) for a in t.assignees.all()],
        "created_by": member_brief(t.created_by),
        "updated_at": _iso(t.updated_at),
        "pill": task_pill(t),
    }


def task_update_json(u):
    return {
        "id": u.pk,
        "kind": u.kind,
        "author": member_brief(u.author),
        "body": u.body,
        "from": u.from_value,
        "to": u.to_value,
        "at": _iso(u.created_at),
    }


def _tasks_qs(qs):
    return qs.select_related("committee", "created_by__user").prefetch_related("assignees__user")


def audience_label(a):
    if a.audience == Announcement.ALL:
        return "Everyone"
    if a.audience == Announcement.COMMITTEES:
        return ", ".join(c.name for c in a.committees.all()) or "Committees"
    n = a.people.count()
    return f"{n} {'person' if n == 1 else 'people'}"


def announcement_json(a, perms, receipt=None, full=True):
    data = {
        "id": a.pk,
        "title": a.title,
        "body": a.body if full else a.body[:400],
        "author": member_brief(a.author),
        "posted_as": committee_brief(a.posted_as),
        "audience": a.audience,
        "audience_label": audience_label(a),
        "pinned": a.pinned,
        "urgent": a.urgent,
        "requires_ack": a.requires_ack,
        "created_at": _iso(a.created_at),
        "edited_at": _iso(a.edited_at),
        "is_recipient": receipt is not None,
        "read": bool(receipt and receipt.read_at) or receipt is None,
        "acked": bool(receipt and receipt.acked_at),
        "can_manage": perms.can_manage_announcement(a),
    }
    if data["can_manage"]:
        stats = a.receipts.aggregate(
            total=Count("pk"), read=Count("pk", filter=Q(read_at__isnull=False)),
            acked=Count("pk", filter=Q(acked_at__isnull=False)),
        )
        data["stats"] = stats
    return data


def calendar_url(m):
    fmt = "%Y%m%dT%H%M%SZ"
    start = m.start.astimezone(dt_timezone.utc).strftime(fmt)
    end = m.finish.astimezone(dt_timezone.utc).strftime(fmt)
    details = m.agenda + (f"\n\n{m.online_link}" if m.online_link else "")
    return "https://calendar.google.com/calendar/render?" + urlencode({
        "action": "TEMPLATE", "text": m.title, "dates": f"{start}/{end}",
        "details": details[:1500], "location": m.location or m.online_link,
    })


def meeting_json(m, perms, mine=None):
    counts = {k: 0 for k, _ in Attendee.RSVPS}
    for a in m.attendees.all():
        counts[a.rsvp] = counts.get(a.rsvp, 0) + 1
    if mine is None:
        mine = next((a for a in m.attendees.all() if a.member_id == perms.member.pk), None)
    return {
        "id": m.pk,
        "title": m.title,
        "committee": committee_brief(m.committee),
        "scope_label": m.committee.name if m.committee else "General meeting",
        "start": _iso(m.start),
        "end": _iso(m.end),
        "location": m.location,
        "online_link": m.online_link,
        "status": m.status,
        "cancelled": m.status == Meeting.CANCELLED,
        "is_past": m.is_past,
        "my_rsvp": mine.rsvp if mine else None,
        "counts": counts,
        "has_minutes": bool(m.minutes),
        "can_manage": perms.can_manage_meeting(m),
    }


def _meetings_qs(qs):
    return qs.select_related("committee", "created_by__user").prefetch_related("attendees")


def notification_json(n):
    return {
        "id": n.pk, "kind": n.kind, "object_id": n.object_id, "title": n.title, "body": n.body,
        "at": _iso(n.created_at), "read": n.read_at is not None,
    }


def committee_json(c, perms, counts=None):
    heads = [ms.member for ms in c.memberships.all() if ms.role == Membership.HEAD]
    data = committee_brief(c)
    data.update({
        "description": c.description,
        "member_count": len(c.memberships.all()),
        "heads": [member_brief(h) for h in heads],
        "my_role": next((ms.role for ms in c.memberships.all() if ms.member_id == perms.member.pk), None),
        "can_manage": perms.can_manage_committee(c.pk),
    })
    if counts is not None:
        data.update(counts.get(c.pk, {"open": 0, "overdue": 0}))
    return data


def _committees_qs(perms):
    return perms.committees_visible(Committee.objects.filter(archived=False)).prefetch_related("memberships__member__user")


def _task_counts(perms):
    today = timezone.localdate()
    rows = (
        perms.tasks_visible(Task.objects.exclude(status__in=Task.CLOSED))
        .values("committee_id")
        .annotate(open=Count("pk", distinct=True),
                  overdue=Count("pk", filter=Q(due_date__lt=today), distinct=True))
    )
    return {r["committee_id"]: {"open": r["open"], "overdue": r["overdue"]} for r in rows}


# ======================================================================= auth


def _throttle_key(request, ident=""):
    return f"login-fail:{_ip(request)}", f"login-fail-id:{ident.lower()}"


def _too_many(request, ident=""):
    return any(cache.get(k, 0) >= settings.LOGIN_MAX_ATTEMPTS for k in _throttle_key(request, ident))


def _fail(request, ident=""):
    for k in _throttle_key(request, ident):
        cache.set(k, cache.get(k, 0) + 1, settings.LOGIN_LOCKOUT_SECONDS)


def find_user(identifier):
    ident = (identifier or "").strip()
    if not ident:
        return None
    if "@" in ident:
        return User.objects.filter(email__iexact=ident).first()
    key = phone_digits(ident)
    if len(key) >= 6:
        m = Member.objects.select_related("user").filter(phone_key=key).first()
        if m:
            return m.user
    return User.objects.filter(username__iexact=ident).first()


@api_view(auth=False)
def config(request):
    fb = push.client_options("ios" if request.GET.get("platform") == "ios" else "android")
    return ok({
        "org_name": settings.ORG_NAME,
        "short_name": settings.ORG_SHORT_NAME,
        "time_zone": settings.TIME_ZONE,
        "firebase": fb,
    })


@api_view(methods=("POST",), auth=False)
def login(request):
    ident = text(request.data, "identifier", "Email or phone", 150)
    if _too_many(request, ident):
        return _error("Too many failed attempts. Try again in a few minutes.", 429)
    user = find_user(ident)
    password = str(request.data.get("password", ""))
    if user is not None:
        user = authenticate(request, username=user.username, password=password)
    if not user or not user.is_active or not hasattr(user, "member"):
        _fail(request, ident)
        return _error("Wrong email/phone or password.", 400)
    token = ApiToken.issue(user, device=text(request.data, "device", "Device", 100))
    return ok({"token": token})


@api_view(methods=("POST",), auth=False)
def invite_check(request):
    code = text(request.data, "code", "Invite code", 20, required=True)
    if _too_many(request):
        return _error("Too many attempts. Try again in a few minutes.", 429)
    inv = Invite.find(code)
    if not inv:
        _fail(request)
        return _error("That code isn't valid or has expired. Ask an admin for a new one.", 400)
    m = inv.member
    return ok({"name": m.name, "login": m.user.email or m.phone, "reset": m.user.has_usable_password()})


@api_view(methods=("POST",), auth=False)
def invite_accept(request):
    code = text(request.data, "code", "Invite code", 20, required=True)
    if _too_many(request):
        return _error("Too many attempts. Try again in a few minutes.", 429)
    inv = Invite.find(code)
    if not inv:
        _fail(request)
        return _error("That code isn't valid or has expired. Ask an admin for a new one.", 400)
    user = inv.member.user
    password = str(request.data.get("password", ""))
    try:
        validate_password(password, user)
    except ValidationError as e:
        raise Bad({"password": list(e.messages)})
    with transaction.atomic():
        user.set_password(password)
        user.is_active = True
        user.save()
        inv.used_at = timezone.now()
        inv.save(update_fields=["used_at"])
        ApiToken.objects.filter(user=user).delete()  # a reset signs out other phones
    token = ApiToken.issue(user, device=text(request.data, "device", "Device", 100))
    return ok({"token": token})


@api_view(methods=("POST",))
def logout(request):
    request.api_token.delete()
    return ok()


@api_view(methods=("POST",))
def delete_account(request):
    """Deletes the signed-in member's personal data (required by the app stores).

    Their name, contact details and password go; work they wrote stays, shown as "Former member"."""
    me = request.member
    user = me.user
    if not user.check_password(str(request.data.get("password", ""))):
        raise Bad({"password": ["Your password is not correct."]})
    if me.is_developer:
        raise Denied("The developer account can't be deleted from the app.")
    with transaction.atomic():
        ApiToken.objects.filter(user=user).delete()
        Device.objects.filter(member=me).delete()
        Invite.objects.filter(member=me).delete()
        Membership.objects.filter(member=me).delete()
        Notification.objects.filter(member=me).delete()
        Attendee.objects.filter(member=me, meeting__start__gte=timezone.now()).delete()
        me.name, me.phone, me.title, me.is_admin = "Former member", "", "", False
        me.save()
        user.username = f"deleted-{user.pk}"
        user.email = user.first_name = user.last_name = ""
        user.is_active = False
        user.set_unusable_password()
        user.save()
    return ok()


@api_view(methods=("POST",))
def change_password(request):
    user = request.member.user
    if not user.check_password(str(request.data.get("old_password", ""))):
        raise Bad({"old_password": ["Your current password is not correct."]})
    new = str(request.data.get("new_password", ""))
    try:
        validate_password(new, user)
    except ValidationError as e:
        raise Bad({"new_password": list(e.messages)})
    user.set_password(new)
    user.save()
    ApiToken.objects.filter(user=user).exclude(pk=request.api_token.pk).delete()
    return ok()


@api_view(methods=("POST",))
def devices(request):
    token = text(request.data, "token", "Token", 300, required=True)
    if request.data.get("remove"):
        Device.objects.filter(token=token, member=request.member).delete()
        return ok()
    Device.objects.update_or_create(
        token=token, defaults={"member": request.member, "api_token": request.api_token}
    )
    return ok()


# ======================================================================= bootstrap & home


@api_view()
def bootstrap(request):
    p = request.perms
    me = request.member
    committees = list(_committees_qs(p))
    members = p.people_visible(Member.objects.filter(user__is_active=True)).select_related("user")
    return ok({
        "org_name": settings.ORG_NAME,
        "short_name": settings.ORG_SHORT_NAME,
        "me": {**member_json(me), "is_core": p.core, "headed_ids": sorted(p.headed_ids),
               "can_lead": p.can_lead(), "can_manage_people": p.can_manage_people()},
        "leadable_ids": sorted(p.leadable_committee_ids()),
        "committees": [committee_brief(c) for c in committees],
        "members": [
            {**member_brief(m), "committee_ids": [ms.committee_id for ms in m.memberships.all()]}
            for m in members.prefetch_related("memberships")
        ],
        "counts": _counts(me),
        "choices": {
            "statuses": [{"value": v, "label": l} for v, l in Task.STATUSES],
            "priorities": [{"value": v, "label": l} for v, l in Task.PRIORITIES],
            "colors": [v for v, _ in COLORS],
            "rsvps": [{"value": v, "label": l} for v, l in Attendee.RSVPS if v != Attendee.PENDING],
            "attendance": [{"value": v, "label": l} for v, l in Attendee.ATTENDANCE if v],
        },
        "push": push.enabled(),
    })


def _counts(me):
    return {
        "notifications": Notification.objects.filter(member=me, read_at__isnull=True).count(),
        "announcements": Receipt.objects.filter(member=me, read_at__isnull=True).count(),
        "to_ack": Receipt.objects.filter(
            member=me, acked_at__isnull=True, announcement__requires_ack=True
        ).count(),
        "rsvp": Attendee.objects.filter(
            member=me, rsvp=Attendee.PENDING, meeting__status=Meeting.SCHEDULED,
            meeting__start__gte=timezone.now(),
        ).count(),
    }


@api_view()
def counts(request):
    return ok(_counts(request.member))


@api_view()
def home(request):
    p, me = request.perms, request.member
    now = timezone.now()
    today = timezone.localdate()

    my_open = _tasks_qs(Task.objects.filter(assignees=me).exclude(status__in=Task.CLOSED))
    my_tasks = sorted(my_open, key=lambda t: (t.due_date or date.max, -t.priority))[:6]
    overdue_visible = p.tasks_visible(Task.objects.exclude(status__in=Task.CLOSED).filter(due_date__lt=today))

    receipts = {
        r.announcement_id: r
        for r in Receipt.objects.filter(member=me, announcement__created_at__gte=now - timedelta(days=60))
        .select_related("announcement")
    }
    ann_qs = p.announcements_visible(Announcement.objects.filter(
        Q(pk__in=[k for k, r in receipts.items() if not r.read_at or (r.announcement.requires_ack and not r.acked_at)])
        | Q(pinned=True)
    )).select_related("author__user", "posted_as").prefetch_related("committees", "people")[:5]
    announcements = [announcement_json(a, p, receipts.get(a.pk), full=False) for a in ann_qs]

    meetings = _meetings_qs(
        p.meetings_visible(Meeting.objects.filter(start__gte=now - timedelta(hours=2), start__lte=now + timedelta(days=30)))
    ).filter(Q(attendees__member=me) | Q(created_by=me)).distinct()[:4]

    overview = []
    if p.can_lead():
        cnt = _task_counts(p)
        ids = p.leadable_committee_ids()
        for c in _committees_qs(p):
            if c.pk in ids:
                overview.append(committee_json(c, p, cnt))

    c = _counts(me)
    return ok({
        "name": me.name.split(" ")[0],
        "today": today.isoformat(),
        "stats": {
            "my_open": my_open.count(),
            "overdue": overdue_visible.count(),
            "unread": c["announcements"],
            "meetings": Meeting.objects.filter(
                attendees__member=me, status=Meeting.SCHEDULED, start__gte=now, start__lte=now + timedelta(days=7)
            ).count(),
        },
        "counts": c,
        "my_tasks": [task_json(t) for t in my_tasks],
        "announcements": announcements,
        "meetings": [meeting_json(m, p) for m in meetings],
        "overview": overview,
    })


# ======================================================================= tasks


def _assignable(perms, committee, ids):
    if not ids:
        return []
    people = list(perms.people_visible(Member.objects.filter(pk__in=ids, user__is_active=True)))
    if len(people) != len(set(ids)):
        raise Bad({"assignees": ["Someone in the list was not found."]})
    if not perms.core:
        allowed = set(Membership.objects.filter(committee=committee).values_list("member_id", flat=True))
        if any(m.pk not in allowed for m in people):
            raise Bad({"assignees": ["You can only assign people in this committee."]})
    return people


def _committee_for_lead(perms, d, key="committee"):
    try:
        cid = int(d.get(key) or 0)
    except (TypeError, ValueError):
        cid = 0
    c = Committee.objects.filter(pk=cid, archived=False).first()
    if not c:
        raise Bad({key: ["Choose a committee."]})
    if c.pk not in perms.leadable_committee_ids():
        raise Denied("You can only do this for committees you lead.")
    return c


def _desk(committee, people):
    names = ", ".join(p.name for p in people)
    return f"{committee.name} · {names}" if names else committee.name


@api_view(methods=("GET", "POST"))
def tasks(request):
    p, me = request.perms, request.member
    if request.method == "POST":
        if not p.can_lead():
            raise Denied("Only the core committee and committee heads can create tasks.")
        d = request.data
        title = text(d, "title", "Title", 200, required=True)
        committee = _committee_for_lead(p, d)
        people = _assignable(p, committee, id_list(d, "assignees"))
        with transaction.atomic():
            t = Task.objects.create(
                title=title,
                description=text(d, "description", "Description", 5000),
                committee=committee,
                created_by=me,
                priority=choice(d, "priority", "Priority", Task.PRIORITIES, 2),
                due_date=date_value(d, "due_date", "Due date"),
            )
            t.assignees.set(people)
            TaskUpdate.objects.create(task=t, author=me, kind=TaskUpdate.CREATED, to_value=_desk(committee, people))
            notify(task_new_audience(t, me), "task", t.pk, f"New task: {t.title}",
                   f"{committee.name}" + (f" · due {t.due_date:%-d %b}" if t.due_date else ""),
                   urgent=t.priority == 4)
        return ok({"task": task_json(t)}, 201)

    q = request.GET
    scope = q.get("scope", "team")
    status = q.get("status", "open")
    qs = p.tasks_visible()
    if scope == "mine":
        qs = qs.filter(assignees=me)
    elif scope == "team":
        qs = qs.filter(Q(committee_id__in=p.committee_ids) | Q(assignees=me) | Q(created_by=me))
    elif scope == "created":
        qs = qs.filter(created_by=me)
    if q.get("committee"):
        qs = qs.filter(committee_id=q.get("committee"))
    if status == "open":
        qs = qs.exclude(status__in=Task.CLOSED)
    elif status == "closed":
        qs = qs.filter(status__in=Task.CLOSED)
    elif status in dict(Task.STATUSES):
        qs = qs.filter(status=status)
    if q.get("q"):
        s = q["q"].strip()
        qs = qs.filter(Q(title__icontains=s) | Q(description__icontains=s))
    qs = _tasks_qs(qs.distinct())
    items = list(qs[:300])
    if status == "closed":
        items.sort(key=lambda t: t.closed_at or t.updated_at, reverse=True)
    else:
        items.sort(key=lambda t: (t.due_date or date.max, -t.priority, -t.pk))
    return ok({"tasks": [task_json(t) for t in items]})


def _task_detail(t, p):
    data = task_json(t)
    data.update({
        "description": t.description,
        "created_at": _iso(t.created_at),
        "timeline": [task_update_json(u) for u in t.updates.select_related("author__user")],
        "can_manage": p.can_manage_task(t),
        "can_work": p.can_work_on_task(t),
    })
    return data


@api_view(methods=("GET", "PATCH", "DELETE"))
def task_detail(request, pk):
    p, me = request.perms, request.member
    t = _get(_tasks_qs(p.tasks_visible()), pk)
    if request.method == "GET":
        return ok({"task": _task_detail(t, p)})
    if not p.can_manage_task(t):
        raise Denied("Only the person who created this task, its committee head or the core committee can change it.")
    if request.method == "DELETE":
        t.delete()
        return ok()
    d = request.data
    changes = []
    if "title" in d:
        t.title = text(d, "title", "Title", 200, required=True)
    if "description" in d:
        t.description = text(d, "description", "Description", 5000)
    if "priority" in d:
        new = choice(d, "priority", "Priority", Task.PRIORITIES)
        if new != t.priority:
            changes.append(f"Priority: {dict(Task.PRIORITIES)[new]}")
        t.priority = new
    if "due_date" in d:
        new = date_value(d, "due_date", "Due date")
        if new != t.due_date:
            changes.append(f"Due date: {new:%-d %b %Y}" if new else "Due date removed")
        t.due_date = new
    with transaction.atomic():
        t.save()
        if changes:
            TaskUpdate.objects.create(task=t, author=me, kind=TaskUpdate.EDIT, body="\n".join(changes))
            notify(task_watchers(t, exclude=me), "task", t.pk, f"Updated: {t.title}", "; ".join(changes))
    return ok({"task": _task_detail(t, p)})


@api_view(methods=("POST",))
def task_status(request, pk):
    p, me = request.perms, request.member
    t = _get(p.tasks_visible(), pk)
    if not p.can_work_on_task(t):
        raise Denied()
    new = choice(request.data, "status", "Status", Task.STATUSES)
    note = text(request.data, "note", "Note", 5000)
    if new == t.status and not note:
        return ok({"task": _task_detail(t, p)})
    old_label = t.get_status_display()
    with transaction.atomic():
        if new != t.status:
            t.status = new
            t.closed_at = timezone.now() if new in Task.CLOSED else None
            t.save()
            TaskUpdate.objects.create(task=t, author=me, kind=TaskUpdate.STATUS, body=note,
                                      from_value=old_label, to_value=t.get_status_display())
            notify(task_watchers(t, exclude=me), "task", t.pk, f"{t.get_status_display()}: {t.title}",
                   f"{me.name}" + (f": {note}" if note else ""))
        else:
            TaskUpdate.objects.create(task=t, author=me, kind=TaskUpdate.COMMENT, body=note)
            t.save(update_fields=["updated_at"])
    return ok({"task": _task_detail(t, p)})


@api_view(methods=("POST",))
def task_comment(request, pk):
    p, me = request.perms, request.member
    t = _get(p.tasks_visible(), pk)
    if not p.can_work_on_task(t):
        raise Denied()
    body = text(request.data, "body", "Comment", 5000, required=True)
    with transaction.atomic():
        TaskUpdate.objects.create(task=t, author=me, kind=TaskUpdate.COMMENT, body=body)
        t.save(update_fields=["updated_at"])
        notify(task_watchers(t, exclude=me), "task", t.pk, f"{me.name} on “{t.title}”", body)
    return ok({"task": _task_detail(t, p)})


@api_view(methods=("POST",))
def task_assign(request, pk):
    p, me = request.perms, request.member
    t = _get(p.tasks_visible(), pk)
    if not p.can_manage_task(t):
        raise Denied()
    d = request.data
    try:
        target = int(d.get("committee") or t.committee_id)
    except (TypeError, ValueError):
        raise Bad({"committee": ["Choose a committee."]})
    committee = _committee_for_lead(p, d) if target != t.committee_id else t.committee
    people = _assignable(p, committee, id_list(d, "assignees"))
    before = _desk(t.committee, list(t.assignees.all()))
    old_ids = set(t.assignees.values_list("pk", flat=True))
    with transaction.atomic():
        t.committee = committee
        t.save()
        t.assignees.set(people)
        after = _desk(committee, people)
        if before != after:
            TaskUpdate.objects.create(task=t, author=me, kind=TaskUpdate.ASSIGN, from_value=before, to_value=after,
                                      body=text(d, "note", "Note", 2000))
            new_people = [x for x in people if x.pk not in old_ids and x.pk != me.pk]
            if not people:
                new_people = task_new_audience(t, me)
            notify(new_people, "task", t.pk, f"Assigned to you: {t.title}" if people else f"New task: {t.title}",
                   committee.name)
    t = _get(_tasks_qs(Task.objects), pk)
    return ok({"task": _task_detail(t, p)})


# ======================================================================= announcements


@api_view(methods=("GET", "POST"))
def announcements(request):
    p, me = request.perms, request.member
    if request.method == "POST":
        if not p.can_lead():
            raise Denied("Only the core committee and committee heads can post announcements.")
        d = request.data
        audience = choice(d, "audience", "Audience", Announcement.AUDIENCES, Announcement.ALL)
        committees, people = [], []
        if audience == Announcement.ALL and not p.core:
            raise Denied("Only the core committee can post to everyone.")
        if audience == Announcement.COMMITTEES:
            ids = set(id_list(d, "committees"))
            committees = list(Committee.objects.filter(pk__in=ids, archived=False))
            if not committees:
                raise Bad({"committees": ["Choose at least one committee."]})
            if not p.core and any(c.pk not in p.headed_ids for c in committees):
                raise Denied("You can only post to committees you head.")
        if audience == Announcement.PEOPLE:
            people = list(p.people_visible(Member.objects.filter(pk__in=id_list(d, "people"), user__is_active=True)))
            if not people:
                raise Bad({"people": ["Choose at least one person."]})
            if not p.core:
                allowed = set(Membership.objects.filter(committee_id__in=p.headed_ids).values_list("member_id", flat=True))
                if any(x.pk not in allowed for x in people):
                    raise Denied("You can only message people in committees you head.")
        posted_as = None
        if d.get("posted_as"):
            posted_as = _committee_for_lead(p, d, "posted_as")
        elif p.core:
            posted_as = Committee.objects.filter(is_core=True, archived=False).first()
        elif committees:
            posted_as = committees[0]
        with transaction.atomic():
            a = Announcement.objects.create(
                title=text(d, "title", "Title", 200, required=True),
                body=text(d, "body", "Message", 10000, required=True),
                author=me, posted_as=posted_as, audience=audience,
                pinned=flag(d, "pinned") and p.core,
                urgent=flag(d, "urgent"),
                requires_ack=flag(d, "requires_ack"),
            )
            a.committees.set(committees)
            a.people.set(people)
            sent = publish_announcement(a, me)
        receipt = Receipt.objects.filter(announcement=a, member=me).first()
        return ok({"announcement": announcement_json(a, p, receipt), "sent_to": sent}, 201)

    q = request.GET
    qs = p.announcements_visible().select_related("author__user", "posted_as").prefetch_related("committees", "people")
    receipts = {r.announcement_id: r for r in Receipt.objects.filter(member=me)}
    f = q.get("filter", "all")
    if f == "unread":
        qs = qs.filter(receipts__member=me, receipts__read_at__isnull=True)
    elif f == "ack":
        qs = qs.filter(requires_ack=True, receipts__member=me, receipts__acked_at__isnull=True)
    elif f == "sent":
        qs = qs.filter(author=me)
    if q.get("committee"):
        qs = qs.filter(Q(committees__id=q["committee"]) | Q(posted_as_id=q["committee"]))
    if q.get("q"):
        s = q["q"].strip()
        qs = qs.filter(Q(title__icontains=s) | Q(body__icontains=s))
    items = list(qs.distinct()[:200])
    return ok({"announcements": [announcement_json(a, p, receipts.get(a.pk), full=False) for a in items]})


@api_view(methods=("GET", "PATCH", "DELETE"))
def announcement_detail(request, pk):
    p, me = request.perms, request.member
    a = _get(p.announcements_visible().select_related("author__user", "posted_as"), pk)
    receipt = Receipt.objects.filter(announcement=a, member=me).first()
    if request.method == "GET":
        if receipt and not receipt.read_at:
            receipt.read_at = timezone.now()
            receipt.save(update_fields=["read_at"])
            Notification.objects.filter(member=me, kind="announcement", object_id=a.pk, read_at__isnull=True).update(
                read_at=timezone.now()
            )
        return ok({"announcement": announcement_json(a, p, receipt)})
    if not p.can_manage_announcement(a):
        raise Denied()
    if request.method == "DELETE":
        a.delete()
        return ok()
    d = request.data
    if "title" in d:
        a.title = text(d, "title", "Title", 200, required=True)
    if "body" in d:
        a.body = text(d, "body", "Message", 10000, required=True)
    if "pinned" in d and p.core:
        a.pinned = flag(d, "pinned")
    if "urgent" in d:
        a.urgent = flag(d, "urgent")
    if "requires_ack" in d:
        a.requires_ack = flag(d, "requires_ack")
    if "title" in d or "body" in d:
        a.edited_at = timezone.now()
    a.save()
    return ok({"announcement": announcement_json(a, p, receipt)})


@api_view(methods=("POST",))
def announcement_ack(request, pk):
    p, me = request.perms, request.member
    a = _get(p.announcements_visible(), pk)
    r = Receipt.objects.filter(announcement=a, member=me).first()
    if not r:
        raise Denied("This announcement wasn't sent to you.")
    now = timezone.now()
    r.read_at = r.read_at or now
    r.acked_at = r.acked_at or now
    r.save()
    return ok({"announcement": announcement_json(a, p, r)})


@api_view()
def announcement_receipts(request, pk):
    p = request.perms
    a = _get(p.announcements_visible(), pk)
    if not p.can_manage_announcement(a):
        raise Denied()
    rows = a.receipts.select_related("member__user").order_by("member__name")
    return ok({"receipts": [
        {"member": member_brief(r.member), "read_at": _iso(r.read_at), "acked_at": _iso(r.acked_at)} for r in rows
    ]})


# ======================================================================= meetings


def _meeting_detail(m, p):
    data = meeting_json(m, p)
    data.update({
        "agenda": m.agenda,
        "minutes": m.minutes,
        "minutes_by": member_brief(m.minutes_by),
        "minutes_at": _iso(m.minutes_at),
        "created_by": member_brief(m.created_by),
        "calendar_url": calendar_url(m),
        "attendees": [
            {"member": member_brief(a.member), "rsvp": a.rsvp, "attendance": a.attendance}
            for a in m.attendees.select_related("member__user")
        ],
    })
    return data


def _meeting_fields(m, d, partial=False):
    if not partial or "title" in d:
        m.title = text(d, "title", "Title", 200, required=True)
    if not partial or "agenda" in d:
        m.agenda = text(d, "agenda", "Agenda", 5000)
    if not partial or "start" in d:
        m.start = datetime_value(d, "start", "Start", required=True)
    if not partial or "end" in d:
        m.end = datetime_value(d, "end", "End")
    if m.end and m.end <= m.start:
        raise Bad({"end": ["The end must be after the start."]})
    if not partial or "location" in d:
        m.location = text(d, "location", "Location", 200)
    if not partial or "online_link" in d:
        link = text(d, "online_link", "Online link", 300)
        if link:
            try:
                URLValidator(schemes=["http", "https"])(link)
            except ValidationError:
                raise Bad({"online_link": ["Enter a full link starting with https://"]})
        m.online_link = link


@api_view(methods=("GET", "POST"))
def meetings(request):
    p, me = request.perms, request.member
    if request.method == "POST":
        if not p.can_lead():
            raise Denied("Only the core committee and committee heads can call meetings.")
        d = request.data
        committee = None
        if d.get("committee"):
            committee = _committee_for_lead(p, d)
        elif not p.core:
            raise Denied("Only the core committee can call a general meeting.")
        m = Meeting(committee=committee, created_by=me)
        _meeting_fields(m, d)
        with transaction.atomic():
            m.save()
            invite_to_meeting(m, me)
        return ok({"meeting": _meeting_detail(m, p)}, 201)

    q = request.GET
    now = timezone.now()
    qs = _meetings_qs(p.meetings_visible())
    if q.get("committee"):
        qs = qs.filter(committee_id=q["committee"]) if q["committee"] != "general" else qs.filter(committee__isnull=True)
    if q.get("when", "upcoming") == "past":
        qs = qs.filter(start__lt=now - timedelta(hours=3)).order_by("-start")
    else:
        qs = qs.filter(start__gte=now - timedelta(hours=3)).order_by("start")
    return ok({"meetings": [meeting_json(m, p) for m in qs[:200]]})


@api_view(methods=("GET", "PATCH"))
def meeting_detail(request, pk):
    p, me = request.perms, request.member
    m = _get(_meetings_qs(p.meetings_visible()), pk)
    if request.method == "GET":
        Notification.objects.filter(member=me, kind="meeting", object_id=m.pk, read_at__isnull=True).update(
            read_at=timezone.now()
        )
        return ok({"meeting": _meeting_detail(m, p)})
    if not p.can_manage_meeting(m):
        raise Denied()
    before = (m.start, m.end, m.location, m.online_link)
    _meeting_fields(m, request.data, partial=True)
    with transaction.atomic():
        m.save()
        if (m.start, m.end, m.location, m.online_link) != before:
            when = timezone.localtime(m.start).strftime("%a %-d %b, %H:%M")
            notify([a.member for a in m.attendees.select_related("member") if a.member_id != me.pk],
                   "meeting", m.pk, f"Changed: {m.title}", f"{when}" + (f" · {m.location}" if m.location else ""))
    return ok({"meeting": _meeting_detail(m, p)})


@api_view(methods=("POST",))
def meeting_cancel(request, pk):
    p, me = request.perms, request.member
    m = _get(p.meetings_visible(), pk)
    if not p.can_manage_meeting(m):
        raise Denied()
    restore = flag(request.data, "restore")
    m.status = Meeting.SCHEDULED if restore else Meeting.CANCELLED
    with transaction.atomic():
        m.save()
        when = timezone.localtime(m.start).strftime("%a %-d %b, %H:%M")
        notify([a.member for a in m.attendees.select_related("member") if a.member_id != me.pk], "meeting", m.pk,
               f"{'Back on' if restore else 'Cancelled'}: {m.title}", when)
    m = _get(_meetings_qs(Meeting.objects), pk)
    return ok({"meeting": _meeting_detail(m, p)})


@api_view(methods=("POST",))
def meeting_rsvp(request, pk):
    p, me = request.perms, request.member
    m = _get(p.meetings_visible(), pk)
    a = Attendee.objects.filter(meeting=m, member=me).first()
    if not a:
        if not p.can_manage_meeting(m):
            raise Denied("You're not invited to this meeting.")
        a = Attendee(meeting=m, member=me)
    a.rsvp = choice(request.data, "rsvp", "Reply", Attendee.RSVPS)
    a.save()
    m = _get(_meetings_qs(Meeting.objects), pk)
    return ok({"meeting": _meeting_detail(m, p)})


@api_view(methods=("POST",))
def meeting_attendance(request, pk):
    p = request.perms
    m = _get(p.meetings_visible(), pk)
    if not p.can_manage_meeting(m):
        raise Denied()
    marks = request.data.get("attendance")
    if not isinstance(marks, dict):
        raise Bad({"attendance": ["Send {member_id: status}."]})
    valid = dict(Attendee.ATTENDANCE)
    with transaction.atomic():
        for mid, status in marks.items():
            if status not in valid:
                raise Bad({"attendance": ["Unknown attendance value."]})
            Attendee.objects.filter(meeting=m, member_id=int(mid)).update(attendance=status)
    m = _get(_meetings_qs(Meeting.objects), pk)
    return ok({"meeting": _meeting_detail(m, p)})


@api_view(methods=("POST",))
def meeting_minutes(request, pk):
    p, me = request.perms, request.member
    m = _get(p.meetings_visible(), pk)
    if not p.can_manage_meeting(m):
        raise Denied()
    first = not m.minutes
    m.minutes = text(request.data, "minutes", "Minutes", 20000)
    m.minutes_by = me
    m.minutes_at = timezone.now()
    with transaction.atomic():
        m.save()
        if first and m.minutes:
            notify([a.member for a in m.attendees.select_related("member") if a.member_id != me.pk],
                   "meeting", m.pk, f"Minutes: {m.title}", m.minutes)
    m = _get(_meetings_qs(Meeting.objects), pk)
    return ok({"meeting": _meeting_detail(m, p)})


# ======================================================================= committees


def _committee_fields(c, d, partial=False):
    if not partial or "name" in d:
        name = text(d, "name", "Name", 80, required=True)
        if Committee.objects.filter(name__iexact=name).exclude(pk=c.pk).exists():
            raise Bad({"name": ["A committee with this name already exists."]})
        c.name = name
    if not partial or "description" in d:
        c.description = text(d, "description", "Description", 2000)
    if not partial or "color" in d:
        c.color = choice(d, "color", "Colour", COLORS, "teal")


@api_view(methods=("GET", "POST"))
def committees(request):
    p = request.perms
    if request.method == "POST":
        if not p.core:
            raise Denied("Only the core committee can add committees.")
        c = Committee(order=Committee.objects.count())
        _committee_fields(c, request.data)
        c.save()
        c = _get(_committees_qs(p), c.pk)
        return ok({"committee": committee_json(c, p, {})}, 201)
    counts = _task_counts(p)
    return ok({"committees": [committee_json(c, p, counts) for c in _committees_qs(p)]})


@api_view(methods=("GET", "PATCH", "DELETE"))
def committee_detail(request, pk):
    p, me = request.perms, request.member
    c = _get(_committees_qs(p), pk)
    if request.method == "DELETE":
        if not p.core or c.is_core:
            raise Denied()
        c.archived = True
        c.save()
        return ok()
    if request.method == "PATCH":
        if not p.core:
            raise Denied("Only the core committee can edit committees.")
        _committee_fields(c, request.data, partial=True)
        c.save()
    data = committee_json(c, p, _task_counts(p))
    data["members"] = [
        {**member_brief(ms.member), "role": ms.role, "position": ms.position}
        for ms in c.memberships.all()
        if ms.member.user.is_active
    ]
    open_tasks = _tasks_qs(p.tasks_visible(Task.objects.filter(committee=c).exclude(status__in=Task.CLOSED)))
    data["tasks"] = [task_json(t) for t in sorted(open_tasks, key=lambda t: (t.due_date or date.max, -t.priority))[:30]]
    data["meetings"] = [
        meeting_json(m, p)
        for m in _meetings_qs(p.meetings_visible(Meeting.objects.filter(committee=c, start__gte=timezone.now())))[:5]
    ]
    receipts = {r.announcement_id: r for r in Receipt.objects.filter(member=me)}
    anns = p.announcements_visible(
        Announcement.objects.filter(Q(committees=c) | Q(posted_as=c))
    ).select_related("author__user", "posted_as").prefetch_related("committees", "people").distinct()[:5]
    data["announcements"] = [announcement_json(a, p, receipts.get(a.pk), full=False) for a in anns]
    return ok({"committee": data})


def _check_core_change(p, c, role=None):
    if c.is_core and not p.admin:
        raise Denied("Only an admin can change who is on the core committee.")
    if role == Membership.HEAD and not p.core:
        raise Denied("Only the core committee can appoint heads.")


@api_view(methods=("POST",))
def committee_members(request, pk):
    p = request.perms
    c = _get(Committee.objects.filter(archived=False), pk)
    if not p.can_manage_committee(c.pk):
        raise Denied()
    d = request.data
    role = choice(d, "role", "Role", Membership.ROLES, Membership.MEMBER)
    _check_core_change(p, c, role)
    ids = id_list(d, "members") or ([int(d["member"])] if d.get("member") else [])
    people = list(p.people_visible(Member.objects.filter(pk__in=ids, user__is_active=True)))
    if not people:
        raise Bad({"members": ["Choose at least one person."]})
    for m in people:
        Membership.objects.update_or_create(
            member=m, committee=c, defaults={"role": role, "position": text(d, "position", "Position", 60)}
        )
    return ok()


@api_view(methods=("PATCH", "DELETE"))
def committee_member(request, pk, member_pk):
    p = request.perms
    c = _get(Committee.objects.filter(archived=False), pk)
    ms = Membership.objects.filter(committee=c, member_id=member_pk).first()
    if not ms:
        raise Http404
    if not p.can_manage_committee(c.pk):
        raise Denied()
    if request.method == "DELETE":
        _check_core_change(p, c, ms.role)
        ms.delete()
        return ok()
    d = request.data
    if "role" in d:
        role = choice(d, "role", "Role", Membership.ROLES)
        if role != ms.role:
            _check_core_change(p, c, Membership.HEAD)
        ms.role = role
    if "position" in d:
        ms.position = text(d, "position", "Position", 60)
    ms.save()
    return ok()


# ======================================================================= members


def _unique_username(base):
    base = re.sub(r"[^\w.@+-]", "", base)[:140] or "member"
    name, n = base, 1
    while User.objects.filter(username__iexact=name).exists():
        n += 1
        name = f"{base}{n}"
    return name


def _member_contact(d, member=None):
    email = text(d, "email", "Email", 150).lower()
    phone = text(d, "phone", "Phone", 30)
    if email:
        try:
            validate_email(email)
        except ValidationError:
            raise Bad({"email": ["Enter a valid email address."]})
        clash = User.objects.filter(email__iexact=email)
        if member:
            clash = clash.exclude(pk=member.user_id)
        if clash.exists():
            raise Bad({"email": ["Someone already uses this email."]})
    if phone:
        if not re.fullmatch(r"[0-9+()\-\s.]{6,30}", phone):
            raise Bad({"phone": ["Use digits, spaces and + only."]})
        clash = Member.objects.filter(phone_key=phone_digits(phone))
        if member:
            clash = clash.exclude(pk=member.pk)
        if clash.exists():
            raise Bad({"phone": ["Someone already uses this phone number."]})
    if not email and not phone:
        raise Bad({"email": ["Enter an email or a phone number so they can log in."]})
    return email, phone


def invite_message(member, code):
    login = member.user.email or member.phone
    host = (settings.ALLOWED_HOSTS or ["your server"])[0]
    return (
        f"Assalamu alaikum {member.name.split(' ')[0]},\n\n"
        f"You've been added to the {settings.ORG_SHORT_NAME} app.\n"
        f"1. Install the app (ask the admin for the link).\n"
        f"2. Tap “I have an invite code” and enter: {code}\n"
        f"3. Choose your password. Next time, log in with {login}.\n\n"
        f"The code works once and expires in {settings.INVITE_DAYS} days.\nServer: {host}"
    )


@api_view(methods=("GET", "POST"))
def members(request):
    p, me = request.perms, request.member
    if request.method == "POST":
        if not p.can_manage_people():
            raise Denied("Only admins and the core committee can add people.")
        d = request.data
        name = text(d, "name", "Name", 120, required=True)
        email, phone = _member_contact(d)
        roles = d.get("committees") or []
        if not isinstance(roles, list):
            raise Bad({"committees": ["Send a list."]})
        wanted = []
        for r in roles:
            try:
                c = Committee.objects.get(pk=int(r.get("id")), archived=False)
            except (Committee.DoesNotExist, TypeError, ValueError, AttributeError):
                raise Bad({"committees": ["Unknown committee."]})
            role = Membership.HEAD if r.get("role") == Membership.HEAD else Membership.MEMBER
            _check_core_change(p, c, role)
            wanted.append((c, role))
        with transaction.atomic():
            user = User(username=_unique_username(email or f"p{phone_digits(phone)}"), email=email,
                        first_name=name[:150])
            user.set_unusable_password()
            user.save()
            m = user.member  # created by the post_save hook in apps.py
            m.name, m.phone, m.title = name, phone, text(d, "title", "Title", 80)
            m.is_admin = flag(d, "is_admin") and p.admin
            m.save()
            for c, role in wanted:
                Membership.objects.create(member=m, committee=c, role=role)
            code = Invite.issue(m, by=me)
        return ok({"member": member_json(m), "code": code, "message": invite_message(m, code)}, 201)

    qs = p.people_visible(Member.objects.filter(is_developer=False)).select_related("user").prefetch_related("memberships__committee")
    if not (request.GET.get("all") and p.can_manage_people()):
        qs = qs.filter(user__is_active=True)
    if request.GET.get("committee"):
        qs = qs.filter(memberships__committee_id=request.GET["committee"])
    return ok({"members": [member_json(m) for m in qs.distinct()]})


def _people_for(perms):
    return perms.people_visible(Member.objects.select_related("user"))


@api_view(methods=("GET", "PATCH"))
def member_detail(request, pk):
    p, me = request.perms, request.member
    m = _get(_people_for(p), pk)
    if request.method == "GET":
        data = member_json(m)
        data["open_tasks"] = [
            task_json(t)
            for t in _tasks_qs(p.tasks_visible(Task.objects.filter(assignees=m).exclude(status__in=Task.CLOSED)))[:20]
        ]
        data["invite_pending"] = m.invites.filter(used_at__isnull=True, expires_at__gt=timezone.now()).exists()
        data["can_manage"] = p.can_manage_people() and (p.admin or not m.admin)
        return ok({"member": data})
    is_self = m.pk == me.pk
    if not (is_self or (p.can_manage_people() and (p.admin or not m.admin))):
        raise Denied()
    d = request.data
    if "email" in d or "phone" in d:
        merged = {"email": d.get("email", m.user.email), "phone": d.get("phone", m.phone)}
        email, phone = _member_contact(merged, m)
        m.user.email = email
        m.phone = phone
    if "name" in d:
        m.name = text(d, "name", "Name", 120, required=True)
    if "title" in d:
        m.title = text(d, "title", "Title", 80)
    if "is_admin" in d and p.admin and not is_self:
        m.is_admin = flag(d, "is_admin")
    if "active" in d and not is_self:
        if not p.admin:
            raise Denied("Only an admin can deactivate people.")
        m.user.is_active = flag(d, "active")
        if not m.user.is_active:
            ApiToken.objects.filter(user=m.user).delete()
            Device.objects.filter(member=m).delete()
    with transaction.atomic():
        m.user.save()
        m.save()
    return ok({"member": member_json(m)})


@api_view(methods=("POST",))
def member_invite(request, pk):
    p, me = request.perms, request.member
    m = _get(_people_for(p), pk)
    if not p.can_manage_people() or (m.admin and not p.admin):
        raise Denied()
    code = Invite.issue(m, by=me)
    return ok({"code": code, "message": invite_message(m, code)})


# ======================================================================= inbox


@api_view()
def notifications(request):
    me = request.member
    items = Notification.objects.filter(member=me)[:60]
    return ok({"notifications": [notification_json(n) for n in items], "counts": _counts(me)})


@api_view(methods=("POST",))
def notifications_read(request):
    me = request.member
    qs = Notification.objects.filter(member=me, read_at__isnull=True)
    ids = id_list(request.data, "ids")
    if ids:
        qs = qs.filter(pk__in=ids)
    qs.update(read_at=timezone.now())
    return ok({"counts": _counts(me)})
