"""The public side of the app: anyone can read it; registering (phone + password) is optional.

Members' data never appears here except names, wings, positions/designations and responsibility
titles in Who's who: no phone numbers or emails.
"""

from datetime import timedelta

from django.contrib.auth.models import User
from django.contrib.auth.password_validation import validate_password
from django.core.exceptions import ValidationError
from django.db import transaction
from django.db.models import Q
from django.utils import timezone

from . import push
from .api import (
    Bad,
    Denied,
    _fail,
    _get,
    _iso,
    _too_many,
    _unique_username,
    api_view,
    datetime_value,
    flag,
    invite_message,
    member_brief,
    ok,
    text,
)
from .models import (
    ApiToken,
    Committee,
    Grant,
    Invite,
    Member,
    PasswordResetRequest,
    Program,
    ProgramResource,
    PublicPost,
    Responsibility,
    phone_digits,
)
from .services import Perms, active_members, notify


def _viewer(request):
    """The signed-in person, if the request carries a valid token (public endpoints don't require one)."""
    header = request.headers.get("Authorization", "")
    raw = header[7:].strip() if header.lower().startswith("bearer ") else ""
    if not raw:
        return None, None
    token = ApiToken.objects.select_related("user__member").filter(key_hash=ApiToken.hash(raw)).first()
    if not token or not token.user.is_active or not hasattr(token.user, "member"):
        return None, None
    return token.user.member, Perms(token.user.member)


def _publisher(request):
    me, p = _viewer(request)
    if not me or not p.has(Grant.PUBLIC):
        raise Denied("You don't have permission to publish public content.")
    return me, p


def _url(d, key, label):
    from django.core.validators import URLValidator

    v = text(d, key, label, 500)
    if v:
        try:
            URLValidator(schemes=["http", "https"])(v)
        except ValidationError:
            raise Bad({key: ["Enter a full link starting with https://"]})
    return v


def post_json(x):
    return {
        "id": x.pk, "kind": x.kind, "kind_label": x.get_kind_display(), "title": x.title, "body": x.body,
        "starts_at": _iso(x.starts_at), "ends_at": _iso(x.ends_at), "location": x.location, "link": x.link,
        "category": x.category, "program": {"id": x.program_id, "name": x.program.name} if x.program_id else None,
        "pinned": x.pinned, "is_live": x.is_live, "created_at": _iso(x.created_at),
    }


def program_json(pr, full=False):
    data = {
        "id": pr.pk, "name": pr.name, "short_name": pr.short_name, "description": pr.description,
        "schedule": pr.schedule, "location": pr.location, "registration_url": pr.registration_url,
        "active": pr.active,
    }
    if full:
        data["resources"] = [{"id": r.pk, "title": r.title, "url": r.url, "at": _iso(r.created_at)}
                             for r in pr.resources.all()]
        data["videos"] = [post_json(x) for x in pr.posts.filter(kind=PublicPost.VIDEO)[:20]]
        data["upcoming"] = [post_json(x) for x in pr.posts.filter(
            kind__in=[PublicPost.EVENT, PublicPost.LIVE], starts_at__gte=timezone.now() - timedelta(hours=3))
            .order_by("starts_at")[:10]]
    return data


# ----------------------------------------------------------------------- reading


@api_view(auth=False)
def home(request):
    me, p = _viewer(request)
    now = timezone.now()
    posts = PublicPost.objects.select_related("program")
    live = [x for x in posts.filter(kind=PublicPost.LIVE, created_at__gte=now - timedelta(days=2)) if x.is_live]
    return ok({
        "live": [post_json(x) for x in live],
        "events": [post_json(x) for x in posts.filter(kind=PublicPost.EVENT, starts_at__gte=now - timedelta(hours=3))
                   .order_by("starts_at")[:10]],
        "news": [post_json(x) for x in posts.filter(kind=PublicPost.NEWS)[:10]],
        "videos": [post_json(x) for x in posts.filter(kind=PublicPost.VIDEO)[:6]],
        "programs": [program_json(pr) for pr in Program.objects.filter(active=True)],
        "can_publish": bool(p and p.has(Grant.PUBLIC)),
        "me": member_brief(me) if me else None,
        "is_member": bool(me and not me.is_public),
    })


@api_view(methods=("GET", "POST"), auth=False)
def posts(request):
    if request.method == "POST":
        me, _ = _publisher(request)
        x = PublicPost(created_by=me)
        _post_fields(x, request.data)
        x.save()
        if flag(request.data, "notify"):
            _announce(x)
        return ok({"post": post_json(x)}, 201)
    qs = PublicPost.objects.select_related("program")
    q = request.GET
    if q.get("kind"):
        qs = qs.filter(kind=q["kind"])
    if q.get("category"):
        qs = qs.filter(category=q["category"])
    if q.get("program"):
        qs = qs.filter(program_id=q["program"])
    return ok({"posts": [post_json(x) for x in qs[:100]]})


def _post_fields(x, d):
    if "kind" in d or not x.pk:
        x.kind = d.get("kind") if d.get("kind") in dict(PublicPost.KINDS) else PublicPost.NEWS
    if "title" in d or not x.pk:
        x.title = text(d, "title", "Title", 200, required=True)
    for key, label, n in (("body", "Text", 5000), ("location", "Place", 200)):
        if key in d:
            setattr(x, key, text(d, key, label, n))
    if "link" in d:
        x.link = _url(d, "link", "Link")
    if "starts_at" in d:
        x.starts_at = datetime_value(d, "starts_at", "Starts")
    if "ends_at" in d:
        x.ends_at = datetime_value(d, "ends_at", "Ends")
    if "category" in d:
        x.category = d.get("category") if d.get("category") in dict(PublicPost.CATEGORIES) else ""
    if "program" in d:
        x.program = Program.objects.filter(pk=d.get("program") or 0).first()
    if "pinned" in d:
        x.pinned = flag(d, "pinned")
    if x.kind in (PublicPost.EVENT, PublicPost.LIVE) and not x.starts_at:
        if x.kind == PublicPost.LIVE:
            x.starts_at = timezone.now()
        else:
            raise Bad({"starts_at": ["When does it start?"]})
    if x.kind in (PublicPost.LIVE, PublicPost.VIDEO) and not x.link:
        raise Bad({"link": ["Add the YouTube or stream link."]})


def _announce(x):
    """Push to every phone with the app (topic), and put it in signed-in people's inbox."""
    label = {PublicPost.LIVE: "LIVE now", PublicPost.EVENT: "Event", PublicPost.VIDEO: "New video"}.get(x.kind, "News")
    title = f"{label}: {x.title}"
    body = x.location or x.body
    people = Member.objects.filter(user__is_active=True, is_demo=False, is_developer=False)
    notify(list(people), "public", x.pk, title, body, urgent=x.kind == PublicPost.LIVE, push_each=False)
    push.send_topic_async("public", "public", x.pk, title, body[:140], urgent=x.kind == PublicPost.LIVE)


@api_view(methods=("GET", "PATCH", "DELETE"), auth=False)
def post_detail(request, pk):
    x = _get(PublicPost.objects.select_related("program"), pk)
    if request.method == "GET":
        return ok({"post": post_json(x)})
    _publisher(request)
    if request.method == "DELETE":
        x.delete()
        return ok()
    _post_fields(x, request.data)
    x.save()
    if flag(request.data, "notify"):
        _announce(x)
    return ok({"post": post_json(x)})


@api_view(methods=("GET", "POST"), auth=False)
def programs(request):
    if request.method == "POST":
        _publisher(request)
        pr = Program()
        _program_fields(pr, request.data)
        pr.save()
        return ok({"program": program_json(pr, full=True)}, 201)
    return ok({"programs": [program_json(pr) for pr in Program.objects.filter(active=True)]})


def _program_fields(pr, d):
    if "name" in d or not pr.pk:
        pr.name = text(d, "name", "Name", 120, required=True)
    for key, label, n in (("short_name", "Short name", 20), ("description", "About", 5000),
                          ("schedule", "When", 200), ("location", "Where", 200)):
        if key in d:
            setattr(pr, key, text(d, key, label, n))
    if "registration_url" in d:
        pr.registration_url = _url(d, "registration_url", "Registration link")
    if "active" in d:
        pr.active = flag(d, "active")


@api_view(methods=("GET", "PATCH", "DELETE"), auth=False)
def program_detail(request, pk):
    pr = _get(Program.objects.all(), pk)
    if request.method == "GET":
        return ok({"program": program_json(pr, full=True)})
    _publisher(request)
    if request.method == "DELETE":
        pr.delete()
        return ok()
    _program_fields(pr, request.data)
    pr.save()
    return ok({"program": program_json(pr, full=True)})


@api_view(methods=("POST",), auth=False)
def program_resources(request, pk):
    _publisher(request)
    pr = _get(Program.objects.all(), pk)
    ProgramResource.objects.create(program=pr, title=text(request.data, "title", "Title", 200, required=True),
                                   url=_url(request.data, "url", "Link") or _required_link())
    return ok({"program": program_json(pr, full=True)}, 201)


def _required_link():
    raise Bad({"url": ["Add the link (Google Drive, PDF, YouTube…)."]})


@api_view(methods=("DELETE",), auth=False)
def program_resource(request, pk, rid):
    _publisher(request)
    ProgramResource.objects.filter(program_id=pk, pk=rid).delete()
    return ok()


@api_view(auth=False)
def whoswho(request):
    """Wings, who is in them and their positions, office-bearers and responsibilities. No contact details."""
    people = Member.objects.filter(user__is_active=True, is_developer=False, is_demo=False, is_public=False)
    resp = {}
    for r in Responsibility.objects.filter(active=True, holder__in=people).only("title", "holder_id"):
        resp.setdefault(r.holder_id, []).append(r.title)

    def person(m, position=""):
        return {"id": m.pk, "name": m.name, "designation": m.title, "position": position,
                "member_type": m.member_type, "unit_place": m.unit_place, "responsibilities": resp.get(m.pk, [])}

    def rank(ms):
        order = {"chairman": 0, "asst. chairman": 1, "convenor": 2}
        return (order.get((ms.position or "").lower(), 5 if ms.position else 9), ms.member.name)

    wings = []
    for c in Committee.objects.filter(archived=False, is_demo=False).prefetch_related("memberships__member__user"):
        rows = sorted((ms for ms in c.memberships.all() if ms.member in people), key=rank)
        wings.append({"id": c.pk, "name": c.name, "color": c.color, "description": c.description,
                      "people": [person(ms.member, ms.position) for ms in rows]})
    bearers = [person(m) for m in people.exclude(title="").order_by("name")]
    order = ["president", "vice president", "secretary", "joint secretary", "treasurer"]
    bearers.sort(key=lambda x: (order.index(x["designation"].lower()) if x["designation"].lower() in order else 9,
                                x["name"]))
    return ok({"office_bearers": bearers, "wings": wings})


# ----------------------------------------------------------------------- public accounts


@api_view(methods=("POST",), auth=False)
def register(request):
    d = request.data
    if _too_many(request):
        from django.http import JsonResponse

        return JsonResponse({"error": "Too many attempts. Try again in a few minutes."}, status=429)
    name = text(d, "name", "Name", 120, required=True)
    phone = text(d, "phone", "Mobile number", 30, required=True)
    key = phone_digits(phone)
    if len(key) < 7:
        raise Bad({"phone": ["Enter your full mobile number."]})
    if Member.objects.filter(phone_key=key).exists():
        _fail(request)
        raise Bad({"phone": ["This number is already registered. Sign in, or tap “Forgot password”. "
                             "Members can also use their invite code."]})
    password = str(d.get("password", ""))
    user = User(username=_unique_username(f"p{key}"), first_name=name[:150])
    try:
        validate_password(password, user)
    except ValidationError as e:
        raise Bad({"password": list(e.messages)})
    with transaction.atomic():
        user.set_password(password)
        user.save()
        m = user.member
        m.name, m.phone, m.is_public = name, phone, True
        m.save()
    return ok({"token": ApiToken.issue(user, device=text(d, "device", "Device", 100))}, 201)


@api_view(methods=("POST",), auth=False)
def password_reset_request(request):
    """Anyone can ask; people holding "Handle password resets" (and admins) get the request and send a code."""
    if _too_many(request):
        from django.http import JsonResponse

        return JsonResponse({"error": "Too many attempts. Try again in a few minutes."}, status=429)
    phone = text(request.data, "phone", "Mobile number", 30, required=True)
    key = phone_digits(phone)
    if len(key) < 7:
        raise Bad({"phone": ["Enter your full mobile number."]})
    _fail(request)  # counts towards the per-IP limit, so this can't be used to spam handlers
    m = Member.objects.filter(phone_key=key, is_developer=False, is_demo=False).first()
    if not PasswordResetRequest.objects.filter(phone=phone, handled_at__isnull=True).exists():
        PasswordResetRequest.objects.create(phone=phone, member=m)
        handlers = active_members().filter(Q(grants__perm=Grant.RESETS) | Q(level__in=["admin", "super"])).distinct()
        notify(list(handlers), "reset", None, "Password reset requested",
               f"{m.name if m else 'Unknown number'} · {phone}")
    # Same answer either way: don't reveal whether a number is registered.
    return ok({"message": "Request sent. Someone from the unit will send you a code on WhatsApp or SMS."})


@api_view()
def resets(request):
    p = request.perms
    if not p.has(Grant.RESETS):
        raise Denied()
    rows = PasswordResetRequest.objects.filter(handled_at__isnull=True).select_related("member__user")
    return ok({"requests": [{"id": r.pk, "phone": r.phone, "member": member_brief(r.member) if r.member else None,
                             "is_public": bool(r.member and r.member.is_public), "at": _iso(r.created_at)}
                            for r in rows]})


@api_view(methods=("POST",))
def reset_handle(request, pk):
    p, me = request.perms, request.member
    if not p.has(Grant.RESETS):
        raise Denied()
    r = _get(PasswordResetRequest.objects.filter(handled_at__isnull=True).select_related("member__user"), pk)
    code = message = None
    if r.member and not flag(request.data, "dismiss"):
        if r.member.admin and not p.super:
            raise Denied("Only a super admin can reset an admin's password.")
        code = Invite.issue(r.member, by=me)
        message = invite_message(r.member, code)
    r.handled_at, r.handled_by = timezone.now(), me
    r.save()
    return ok({"code": code, "message": message})

