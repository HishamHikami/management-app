import json
from datetime import timedelta

from django.contrib.auth.models import User
from django.core.cache import cache
from django.test import TestCase, override_settings
from django.utils import timezone

from .models import (
    Announcement,
    ApiToken,
    Attendee,
    Committee,
    Invite,
    Meeting,
    Member,
    Membership,
    Notification,
    Receipt,
    Task,
    phone_digits,
)

PW = "a-good-pass-123"


def make_member(name, email, committees=(), admin=False, phone=""):
    u = User.objects.create_user(username=email, email=email, password=PW, first_name=name)
    m = u.member
    m.name, m.is_admin, m.phone = name, admin, phone
    m.save()
    for c, role in committees:
        Membership.objects.create(member=m, committee=c, role=role)
    return m


class Base(TestCase):
    def setUp(self):
        cache.clear()
        self.core = Committee.objects.create(name="Core", is_core=True)
        self.edu = Committee.objects.create(name="Education")
        self.fin = Committee.objects.create(name="Finance")
        self.admin = make_member("Admin", "admin@x.org", [(self.core, "head")], admin=True, phone="+966 50 111 2222")
        self.corem = make_member("Core Member", "core@x.org", [(self.core, "member")])
        self.head = make_member("Edu Head", "head@x.org", [(self.edu, "head")])
        self.mem = make_member("Edu Member", "mem@x.org", [(self.edu, "member")])
        self.other = make_member("Fin Member", "fin@x.org", [(self.fin, "member")])

    def as_(self, member):
        self.token = ApiToken.issue(member.user)
        return self

    def call(self, method, path, data=None, token=None):
        headers = {"HTTP_AUTHORIZATION": f"Bearer {token or self.token}"}
        fn = getattr(self.client, method)
        if data is not None:
            return fn(f"/api/v1/{path}", data=json.dumps(data), content_type="application/json", **headers)
        return fn(f"/api/v1/{path}", **headers)

    def get(self, path):
        return self.call("get", path)

    def post(self, path, data=None):
        return self.call("post", path, data or {})

    def patch(self, path, data):
        return self.call("patch", path, data)


class AuthTests(Base):
    def test_login_with_email_or_phone(self):
        r = self.client.post("/api/v1/auth/login", json.dumps({"identifier": "ADMIN@x.org", "password": PW}),
                             content_type="application/json")
        self.assertEqual(r.status_code, 200)
        for phone in ("0501112222", "+966501112222", "00966 50 111 2222"):
            r = self.client.post("/api/v1/auth/login", json.dumps({"identifier": phone, "password": PW}),
                                 content_type="application/json")
            self.assertEqual(r.status_code, 200, phone)

    def test_wrong_password_and_lockout(self):
        for _ in range(8):
            r = self.client.post("/api/v1/auth/login", json.dumps({"identifier": "mem@x.org", "password": "no"}),
                                 content_type="application/json")
            self.assertEqual(r.status_code, 400)
        r = self.client.post("/api/v1/auth/login", json.dumps({"identifier": "mem@x.org", "password": PW}),
                             content_type="application/json")
        self.assertEqual(r.status_code, 429)

    def test_requires_token(self):
        self.assertEqual(self.client.get("/api/v1/bootstrap").status_code, 401)
        self.assertEqual(self.client.get("/api/v1/config").status_code, 200)

    def test_phone_key(self):
        self.assertEqual(phone_digits("+966 50 123 4567"), phone_digits("050 123 4567"))

    def test_invite_flow(self):
        self.as_(self.admin)
        r = self.post("members", {"name": "New Person", "phone": "+966 55 999 8888",
                                  "committees": [{"id": self.edu.pk, "role": "member"}]})
        self.assertEqual(r.status_code, 201, r.content)
        code = r.json()["code"]
        self.assertIn(code, r.json()["message"])
        r = self.client.post("/api/v1/auth/invite/check", json.dumps({"code": code.lower()}),
                             content_type="application/json")
        self.assertEqual(r.json()["name"], "New Person")
        r = self.client.post("/api/v1/auth/invite/accept", json.dumps({"code": code, "password": "short"}),
                             content_type="application/json")
        self.assertEqual(r.status_code, 400)
        r = self.client.post("/api/v1/auth/invite/accept", json.dumps({"code": code, "password": PW}),
                             content_type="application/json")
        self.assertEqual(r.status_code, 200)
        # code is single-use; the phone number now logs in
        r = self.client.post("/api/v1/auth/invite/accept", json.dumps({"code": code, "password": PW}),
                             content_type="application/json")
        self.assertEqual(r.status_code, 400)
        r = self.client.post("/api/v1/auth/login", json.dumps({"identifier": "0559998888", "password": PW}),
                             content_type="application/json")
        self.assertEqual(r.status_code, 200)

    def test_members_cannot_invite_people(self):
        self.as_(self.mem)
        r = self.post("members", {"name": "X", "email": "x@x.org"})
        self.assertEqual(r.status_code, 403)

    def test_only_admin_changes_core_committee(self):
        self.as_(self.corem)
        r = self.post(f"committees/{self.core.pk}/members", {"member": self.mem.pk})
        self.assertEqual(r.status_code, 403)
        self.as_(self.admin)
        r = self.post(f"committees/{self.core.pk}/members", {"member": self.mem.pk})
        self.assertEqual(r.status_code, 200)

    def test_bootstrap_roles(self):
        self.as_(self.head)
        me = self.get("bootstrap").json()["me"]
        self.assertFalse(me["is_core"])
        self.assertEqual(me["headed_ids"], [self.edu.pk])
        self.as_(self.corem)
        self.assertTrue(self.get("bootstrap").json()["me"]["is_core"])


class TaskTests(Base):
    def test_core_assigns_and_member_updates(self):
        self.as_(self.corem)
        r = self.post("tasks", {"title": "Plan class", "committee": self.edu.pk, "assignees": [self.mem.pk],
                                "due_date": str(timezone.localdate() + timedelta(days=2))})
        self.assertEqual(r.status_code, 201, r.content)
        tid = r.json()["task"]["id"]
        self.assertTrue(Notification.objects.filter(member=self.mem, kind="task", object_id=tid).exists())

        self.as_(self.mem)
        self.assertEqual(len(self.get("tasks?scope=mine").json()["tasks"]), 1)
        r = self.post(f"tasks/{tid}/status", {"status": "doing", "note": "Started"})
        self.assertEqual(r.json()["task"]["status"], "doing")
        self.assertTrue(Notification.objects.filter(member=self.corem, object_id=tid).exists())
        # members can't edit or delete
        self.assertEqual(self.patch(f"tasks/{tid}", {"title": "x"}).status_code, 403)

        # other committees can't see it
        self.as_(self.other)
        self.assertEqual(self.get(f"tasks/{tid}").status_code, 404)
        self.assertEqual(len(self.get("tasks?scope=all").json()["tasks"]), 0)

    def test_head_limited_to_own_committee(self):
        self.as_(self.head)
        self.assertEqual(self.post("tasks", {"title": "x", "committee": self.fin.pk}).status_code, 403)
        r = self.post("tasks", {"title": "x", "committee": self.edu.pk, "assignees": [self.other.pk]})
        self.assertEqual(r.status_code, 400)
        r = self.post("tasks", {"title": "x", "committee": self.edu.pk})
        self.assertEqual(r.status_code, 201)
        # nobody assigned: the whole committee hears about it
        self.assertTrue(Notification.objects.filter(member=self.mem, kind="task").exists())

    def test_members_cannot_create(self):
        self.as_(self.mem)
        self.assertEqual(self.post("tasks", {"title": "x", "committee": self.edu.pk}).status_code, 403)

    def test_reassign_records_timeline(self):
        self.as_(self.admin)
        tid = self.post("tasks", {"title": "Budget", "committee": self.edu.pk}).json()["task"]["id"]
        r = self.post(f"tasks/{tid}/assign", {"committee": self.fin.pk, "assignees": [self.other.pk]})
        self.assertEqual(r.status_code, 200, r.content)
        t = r.json()["task"]
        self.assertEqual(t["committee"]["id"], self.fin.pk)
        self.assertEqual(t["timeline"][-1]["kind"], "assign")
        self.assertTrue(Notification.objects.filter(member=self.other, object_id=tid).exists())

    def test_comment_and_close(self):
        self.as_(self.admin)
        tid = self.post("tasks", {"title": "T", "committee": self.edu.pk}).json()["task"]["id"]
        self.as_(self.mem)
        self.assertEqual(self.post(f"tasks/{tid}/comments", {"body": "On it"}).status_code, 200)
        r = self.post(f"tasks/{tid}/status", {"status": "done"})
        self.assertTrue(r.json()["task"]["is_closed"])
        self.assertEqual(len(self.get("tasks?status=closed").json()["tasks"]), 1)


class AnnouncementTests(Base):
    def test_everyone_receipts_and_ack(self):
        self.as_(self.corem)
        r = self.post("announcements", {"title": "Gathering", "body": "Friday", "requires_ack": True})
        self.assertEqual(r.status_code, 201, r.content)
        aid = r.json()["announcement"]["id"]
        self.assertEqual(r.json()["sent_to"], Member.objects.count())
        self.assertEqual(Receipt.objects.filter(announcement_id=aid).count(), Member.objects.count())

        self.as_(self.other)
        self.assertEqual(self.get("counts").json()["to_ack"], 1)
        a = self.get(f"announcements/{aid}").json()["announcement"]
        self.assertTrue(a["read"])
        self.assertFalse(a["acked"])
        self.assertNotIn("stats", a)
        self.assertTrue(self.post(f"announcements/{aid}/ack").json()["announcement"]["acked"])
        self.assertEqual(self.get(f"announcements/{aid}/receipts").status_code, 403)

        self.as_(self.corem)
        stats = self.get(f"announcements/{aid}").json()["announcement"]["stats"]
        self.assertEqual(stats["acked"], 1)

    def test_head_posts_only_to_own_committee(self):
        self.as_(self.head)
        self.assertEqual(self.post("announcements", {"title": "x", "body": "y"}).status_code, 403)
        r = self.post("announcements", {"title": "x", "body": "y", "audience": "committees",
                                        "committees": [self.fin.pk]})
        self.assertEqual(r.status_code, 403)
        r = self.post("announcements", {"title": "x", "body": "y", "audience": "committees",
                                        "committees": [self.edu.pk]})
        self.assertEqual(r.status_code, 201)
        aid = r.json()["announcement"]["id"]
        self.as_(self.other)
        self.assertEqual(self.get(f"announcements/{aid}").status_code, 404)
        self.as_(self.mem)
        self.assertEqual(self.get(f"announcements/{aid}").status_code, 200)

    def test_selected_people(self):
        self.as_(self.admin)
        r = self.post("announcements", {"title": "x", "body": "y", "audience": "people", "people": [self.other.pk]})
        self.assertEqual(r.status_code, 201)
        self.assertEqual(Receipt.objects.filter(announcement_id=r.json()["announcement"]["id"]).count(), 1)


class MeetingTests(Base):
    def test_committee_meeting_flow(self):
        self.as_(self.head)
        start = (timezone.localtime() + timedelta(days=2)).replace(microsecond=0, tzinfo=None)
        r = self.post("meetings", {"title": "Weekly", "committee": self.edu.pk, "start": start.isoformat(),
                                   "location": "Hall"})
        self.assertEqual(r.status_code, 201, r.content)
        m = r.json()["meeting"]
        self.assertEqual({a["member"]["id"] for a in m["attendees"]}, {self.head.pk, self.mem.pk})
        self.assertIn("calendar.google.com", m["calendar_url"])

        self.as_(self.mem)
        self.assertEqual(self.get("counts").json()["rsvp"], 1)
        r = self.post(f"meetings/{m['id']}/rsvp", {"rsvp": "going"})
        self.assertEqual(r.json()["meeting"]["my_rsvp"], "going")
        self.assertEqual(self.post(f"meetings/{m['id']}/minutes", {"minutes": "x"}).status_code, 403)

        self.as_(self.other)
        self.assertEqual(self.get(f"meetings/{m['id']}").status_code, 404)

        self.as_(self.head)
        r = self.post(f"meetings/{m['id']}/attendance", {"attendance": {str(self.mem.pk): "present"}})
        self.assertEqual(r.status_code, 200)
        r = self.post(f"meetings/{m['id']}/minutes", {"minutes": "Decided things."})
        self.assertTrue(r.json()["meeting"]["has_minutes"])
        self.assertTrue(Notification.objects.filter(member=self.mem, title__startswith="Minutes").exists())

    def test_general_meeting_needs_core(self):
        start = (timezone.localtime() + timedelta(days=1)).replace(tzinfo=None).isoformat()
        self.as_(self.head)
        self.assertEqual(self.post("meetings", {"title": "AGM", "start": start}).status_code, 403)
        self.as_(self.corem)
        r = self.post("meetings", {"title": "AGM", "start": start})
        self.assertEqual(r.status_code, 201)
        self.assertEqual(Attendee.objects.filter(meeting_id=r.json()["meeting"]["id"]).count(),
                         Member.objects.count())

    def test_cancel_and_reminders(self):
        from django.core.management import call_command

        self.as_(self.admin)
        start = (timezone.localtime() + timedelta(hours=5)).replace(tzinfo=None).isoformat()
        mid = self.post("meetings", {"title": "Soon", "committee": self.edu.pk, "start": start}).json()["meeting"]["id"]
        call_command("send_reminders", stdout=open("/dev/null", "w"))
        self.assertTrue(Meeting.objects.get(pk=mid).reminded)
        self.assertTrue(Notification.objects.filter(member=self.mem, title__startswith="Reminder").exists())
        r = self.post(f"meetings/{mid}/cancel")
        self.assertTrue(r.json()["meeting"]["cancelled"])


class HomeTests(Base):
    def test_home_and_committees(self):
        self.as_(self.admin)
        self.post("tasks", {"title": "T", "committee": self.edu.pk, "assignees": [self.mem.pk],
                            "due_date": str(timezone.localdate() - timedelta(days=1))})
        self.post("announcements", {"title": "A", "body": "B"})
        self.as_(self.mem)
        h = self.get("home").json()
        self.assertEqual(h["stats"]["my_open"], 1)
        self.assertEqual(h["stats"]["overdue"], 1)
        self.assertEqual(len(h["announcements"]), 1)
        self.assertEqual(h["overview"], [])
        self.as_(self.head)
        self.assertEqual([c["id"] for c in self.get("home").json()["overview"]], [self.edu.pk])
        c = self.get(f"committees/{self.edu.pk}").json()["committee"]
        self.assertEqual(c["open"], 1)
        self.assertEqual(len(c["members"]), 2)

    def test_notifications_read(self):
        self.as_(self.admin)
        self.post("announcements", {"title": "A", "body": "B"})
        self.as_(self.mem)
        self.assertEqual(self.get("notifications").json()["counts"]["notifications"], 1)
        self.assertEqual(self.post("notifications/read").json()["counts"]["notifications"], 0)

    def test_deactivate_revokes_access(self):
        self.as_(self.mem)
        tok = self.token
        self.as_(self.admin)
        self.assertEqual(self.patch(f"members/{self.mem.pk}", {"active": False}).status_code, 200)
        self.assertEqual(self.call("get", "bootstrap", token=tok).status_code, 401)


class PushConfigTests(Base):
    @override_settings(FIREBASE_CREDENTIALS="/nonexistent.json", FIREBASE_PROJECT_ID="p", FIREBASE_SENDER_ID="s",
                       FIREBASE_APPS={"android": {"appId": "a-and", "apiKey": "k1"}, "ios": {"appId": "a-ios", "apiKey": "k2"}})
    def test_config_exposes_public_firebase_options_per_platform(self):
        fb = self.client.get("/api/v1/config").json()["firebase"]
        self.assertEqual((fb["projectId"], fb["appId"]), ("p", "a-and"))
        fb = self.client.get("/api/v1/config?platform=ios").json()["firebase"]
        self.assertEqual(fb["appId"], "a-ios")

    def test_push_off_without_settings(self):
        self.assertIsNone(self.client.get("/api/v1/config").json()["firebase"])

    def test_device_registration(self):
        self.as_(self.mem)
        self.assertEqual(self.post("devices", {"token": "abc"}).status_code, 200)
        self.assertEqual(self.mem.devices.count(), 1)
        self.post("devices", {"token": "abc", "remove": True})
        self.assertEqual(self.mem.devices.count(), 0)

    def test_every_new_user_gets_a_member(self):
        import gc

        gc.collect()  # the receiver must survive garbage collection
        u = User.objects.create_user(username="plain", email="plain@x.org", password=PW)
        self.assertTrue(Member.objects.filter(user=u).exists())
        su = User.objects.create_superuser(username="root", email="root@x.org", password=PW)
        self.assertTrue(su.member.admin)

    def test_setup_org_command(self):
        from io import StringIO

        from django.core.management import call_command

        Committee.objects.all().delete()
        out = StringIO()
        call_command("setup_org", name="First Admin", email="first@x.org", stdout=out)
        self.assertTrue(Committee.objects.filter(is_core=True).exists())
        self.assertTrue(Member.objects.get(user__email="first@x.org").is_admin)
        self.assertTrue(Invite.objects.filter(member__user__email="first@x.org").exists())


class DeveloperTests(Base):
    def setUp(self):
        super().setUp()
        from django.core.management import call_command

        self.dev = make_member("Dev", "dev@x.org", [(self.edu, "member")])
        call_command("set_developer", "dev@x.org", stdout=open("/dev/null", "w"))
        self.dev.refresh_from_db()

    def test_full_access_and_out_of_committees(self):
        self.assertTrue(self.dev.is_developer and self.dev.admin)
        self.assertFalse(Membership.objects.filter(member=self.dev).exists())
        self.as_(self.dev)
        me = self.get("bootstrap").json()["me"]
        self.assertTrue(me["is_core"] and me["is_admin"] and me["is_developer"])
        self.assertEqual(self.post("tasks", {"title": "x", "committee": self.fin.pk}).status_code, 201)
        # the developer can still see and edit its own profile
        self.assertEqual(self.get(f"members/{self.dev.pk}").status_code, 200)

    def test_hidden_from_everyone_else(self):
        self.as_(self.admin)
        ids = [m["id"] for m in self.get("members?all=1").json()["members"]]
        self.assertNotIn(self.dev.pk, ids)
        self.assertNotIn(self.dev.pk, [m["id"] for m in self.get("bootstrap").json()["members"]])
        self.assertEqual(self.get(f"members/{self.dev.pk}").status_code, 404)
        self.assertEqual(self.patch(f"members/{self.dev.pk}", {"active": False}).status_code, 404)
        self.assertEqual(self.post(f"members/{self.dev.pk}/invite").status_code, 404)
        r = self.post("announcements", {"title": "All", "body": "x"})
        self.assertFalse(Receipt.objects.filter(announcement_id=r.json()["announcement"]["id"], member=self.dev).exists())
        start = (timezone.localtime() + timedelta(days=1)).replace(tzinfo=None).isoformat()
        mid = self.post("meetings", {"title": "AGM", "start": start}).json()["meeting"]["id"]
        self.assertFalse(Attendee.objects.filter(meeting_id=mid, member=self.dev).exists())
        r = self.post("tasks", {"title": "x", "committee": self.edu.pk, "assignees": [self.dev.pk]})
        self.assertEqual(r.status_code, 400)

    def test_developer_posts_reach_everyone_but_itself(self):
        self.as_(self.dev)
        r = self.post("announcements", {"title": "Hello", "body": "x"})
        self.assertEqual(r.json()["sent_to"], Member.objects.filter(is_developer=False).count())


class ReviewDemoTests(Base):
    def setUp(self):
        super().setUp()
        from io import StringIO

        from django.core.management import call_command

        out = StringIO()
        call_command("setup_review_demo", stdout=out)
        self.pw = out.getvalue().split("password: ")[1].strip()
        r = self.client.post("/api/v1/auth/login", json.dumps({"identifier": "review@ksa-riyadh.halacreative.com",
                                                                "password": self.pw}), content_type="application/json")
        self.reviewer_token = r.json()["token"]

    def test_reviewer_sees_only_demo(self):
        self.token = self.reviewer_token
        b = self.get("bootstrap").json()
        self.assertEqual([c["name"] for c in b["committees"]], ["Demo Committee"])
        self.assertTrue(all("(demo)" in m["name"] or m["name"] == "App Reviewer" for m in b["members"]))
        self.assertFalse(b["me"]["is_core"])
        self.assertEqual(len(self.get("tasks?scope=all&status=any").json()["tasks"]), 4)
        self.assertEqual(self.get(f"members/{self.mem.pk}").status_code, 404)
        self.assertEqual(self.get(f"committees/{self.edu.pk}").status_code, 404)
        self.assertEqual(self.get("home").status_code, 200)
        # the reviewer can try creating things in the demo committee
        demo = b["committees"][0]["id"]
        self.assertEqual(self.post("tasks", {"title": "Try", "committee": demo}).status_code, 201)

    def test_members_never_see_demo(self):
        self.as_(self.admin)
        self.assertNotIn("Demo Committee", [c["name"] for c in self.get("committees").json()["committees"]])
        self.assertFalse(any("demo" in m["name"] for m in self.get("members?all=1").json()["members"]))
        r = self.post("announcements", {"title": "All", "body": "x"})
        self.assertEqual(r.json()["sent_to"], Member.objects.filter(is_demo=False, is_developer=False).count())


class DeleteAccountTests(Base):
    def test_delete_scrubs_personal_data(self):
        self.as_(self.admin)
        tid = self.post("tasks", {"title": "T", "committee": self.edu.pk}).json()["task"]["id"]
        self.as_(self.mem)
        self.post(f"tasks/{tid}/comments", {"body": "hello"})
        self.assertEqual(self.post("auth/delete", {"password": "wrong"}).status_code, 400)
        self.assertEqual(self.post("auth/delete", {"password": PW}).status_code, 200)
        self.mem.refresh_from_db()
        self.mem.user.refresh_from_db()
        self.assertEqual((self.mem.name, self.mem.phone, self.mem.user.email), ("Former member", "", ""))
        self.assertFalse(self.mem.user.is_active or self.mem.user.has_usable_password())
        self.assertFalse(Membership.objects.filter(member=self.mem).exists())
        self.assertEqual(self.get("bootstrap").status_code, 401)
        # their comment is kept, shown as a former member
        self.as_(self.admin)
        tl = self.get(f"tasks/{tid}").json()["task"]["timeline"]
        self.assertEqual(tl[-1]["author"]["name"], "Former member")

    def test_pages(self):
        self.assertContains(self.client.get("/privacy"), "Privacy policy")
        self.assertContains(self.client.get("/account-deletion"), "Delete my account")
