# Next update — owner's notes (collecting; don't build until the list is complete)

1. **Responsibilities (recurring duties)**, next to Tasks.
   Tasks are one-time; responsibilities repeat (a person's or committee's standing duty).
   Open questions to settle before building:
   - Assigned to a person, a committee, or both? Can it rotate between people?
   - Repeat pattern: daily / weekly (which day) / monthly (which date) / custom?
   - Each occurrence checked off as done (with a note), and history kept?
   - Reminders before / on the due day; flag missed occurrences to the head/core?
   - Who creates them: core committee and committee heads (same as tasks)?

Also pending for the next iOS workflow change:
- Build with Xcode 27 / iOS 27 SDK (Apple requires it from April 2027; ITMS-90725 notice on build 106).
- Server allowlist on next deploy: new hashes for android.yml, ios.yml, asc_signing.py.

2. **Public side of the app (no login)**, for anyone who installs it. Members' area stays invite-only.
   - Public announcements about events, and a "Live now / coming up" item (e.g. a YouTube live link).
   - Past videos: add YouTube (or other) video links, shown as a list/gallery.
   - **QHLS — Quran, Hadith, Learning, School**: a recurring class with
     - its schedule (recurring sessions),
     - resources for the public (files and/or links),
     - a **Registration** button that opens an external Google Form (keep it as today).
   Open questions:
   - Who publishes public content: core committee only, or also a "Media" committee / chosen people?
   - Is a public post separate from members' announcements, or can one announcement be marked "also public"?
   - Resources: links only (Google Drive / PDFs elsewhere), or upload files to our server?
   - Live: a link that shows a "LIVE" badge while it's on, plus a push notification to everyone who installed the app?
   - Past videos: one list, or grouped (QHLS sessions, events, lectures)?
   - Notifications for public users (no account): allow them to opt in to event/live alerts?
   - Language of public pages: English only, or also Kannada / Urdu / Arabic?
   Store impact: with a public area the app is no longer members-only, so the plan for Apple's
   *unlisted* distribution changes to a normal public listing (simpler), and both store listings,
   screenshots and privacy texts get updated.

3. **Public accounts and the opening screen** (decided by the owner):
   - Anyone can **register** (optional) to stay connected: receive public announcements and updates.
     Registering is optional; the public area works without it.
   - **Notifications:** no separate opt-in; if the person allows notifications on their phone, that is enough.
   - **Members' invitation login stays exactly as it is**, but it is **not shown prominently**:
     the app opens on the public home (events, live, videos, QHLS), and the members' sign-in /
     invite code sits in a small, discreet place (e.g. a "Members" link in the menu or profile corner),
     so the public never feels the app is only for a select few.
   Open questions:
   - What does public registration ask for: name + phone and/or email? Password, or a one-time code (OTP)?
   - Is a registered public user stored separately from members (recommended), so they never appear in
     the members' directory, tasks or committees?
   - Can the core committee later "promote" a registered public user to a member?
   - Should public users see who else is registered? (Assumed: no.)
