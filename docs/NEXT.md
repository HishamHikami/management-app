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

4. **Public "Who's who"**: visible to everyone (public and members):
   - Every wing/committee, its people and each person's **designation** (e.g. President, Secretary,
     Head of Education), so anyone knows who is responsible for what and can contact them.
   Open questions:
   - "Wing" = the committees in the app (Education, Welfare, …), or are wings a level above committees?
   - Contact details shown to the public: phone / WhatsApp / email for everyone, or only for heads and
     office-bearers, or per person (a "show my number publicly" switch)? (Privacy policy gets updated.)
   - Photos of office-bearers: yes/no?

5. **Member structure from the owner's sheet** (the import itself is done once on the server by the
   droplet session: **no import feature in the app**, and no real data in this repo).
   Sheet layout (structure only): one row per person with
   `Sl. No. | Name | Mobile No. | Unit Place | Member Type | Wing | Position 1 | Position 2 | Comments`.
   What the app needs to model it:
   - **Unit Place**: the local area a person belongs to (8 areas, e.g. Malaz, Batha, Olaya East/West,
     Suwaid, Garnatha, Iskaan). New field on each person, filter in People / Who's who.
   - **Member Type**: *Executive* or *Member*.
   - **Wings**: the sheet's wings (Youth, Dawa, QHLS, Finance, Umrah, Media, Social Media / PRO,
     Social Welfare, Education, Publicity, Career & Sports, ORG). A person can be in **two wings**,
     with **Position 1** for the first and **Position 2** for the second.
   - **Positions**: organisation level *President, Secretary, Treasurer* (office-bearers) and wing level
     *Chairman, Asst. Chairman, Convenor, Member*.
   - **Comments**: private admin notes (e.g. membership form not filled) + a *needs follow-up* flag:
     never public.
   - Some people have no mobile number yet: allowed; they can't be sent an invite until one is added.
   - **People** section: everyone listed with status *Not invited / Invite sent / Active* and a
     **Send invite code** button; only after using the code do they become active users.
   Open questions:
   - Is **Executive** the same as the **core committee** (can assign work, post to everyone)?
   - Wing **Chairman** = head (full control of the wing). Do **Asst. Chairman** and **Convenor** also get
     head rights, or are they designations only?
   - Rename "Committees" to **"Wings"** throughout the app? (Assumed yes.)
   - "EXIT" in the wing column: a person who left; import as inactive?

6. **Administration levels & permissions** (decided by the owner):
   - Levels: **Developer** (owner, hidden) → **Super admin** → **Admin** → **Member** (+ individual permissions).
   - **Nobody gets super admin automatically.** The owner (developer account) is the only one at the
     start and appoints super admins / admins by hand. Only the developer or a super admin can create
     super admins; admins can't create or change admins/super admins.
   - **Member type selector: Executive / Member**, on every person (imported and new). Shown in People
     as a filter / separate sections. When adding a new person: choose the type, and optionally the
     wing(s) and designation (can also be filled in later by whoever invites them).
   - **Executive ⇒ Admin by default** (not super admin). Members ⇒ no extra permissions.
   - **Designations/positions stay as labels** (from the sheet or typed in): they don't grant
     permissions by themselves.
   - Individual permissions an admin/super admin can tick per person, each scoped to *own wing(s)* or
     *all wings*: assign tasks · manage responsibilities · post announcements · call meetings ·
     publish public content · manage wing members.
   - The sheet import (done on the server) lists everyone in People with phone, type, wings and
     designations; status *Not invited* until someone sends their invite code.
   Open question: after the import, should the 18 Executives become admins **straight away** (default
   rule applies), or stay without admin until the owner confirms each one?
