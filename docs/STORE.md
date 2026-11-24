# Store listing — ready to paste

## Names
- **App name:** KSA Riyadh Unit
- **Subtitle (Apple, 30):** Members & committees
- **Short description (Play, 80):** Tasks, announcements and meetings for Karnataka Salafi Association – Riyadh Unit.
- **Developer / seller:** your personal account (shown by the stores)
- **Category:** Productivity (both) · **Price:** Free · **Ads:** none · **In-app purchases:** none
- **Keywords (Apple, 100):** committee,members,association,tasks,announcements,meetings,minutes,attendance,Riyadh,Karnataka

## Full description
The official members' app of **Karnataka Salafi Association – Riyadh Unit**.

Accounts are by invitation only: an admin of the unit adds you and sends you a one-time code.

• **Tasks** — the core committee and committee heads assign work to committees or people. Follow progress from To do to Done, comment, and see the full history.
• **Announcements** — news for everyone, chosen committees or chosen people. Important notices can ask you to confirm you have read them.
• **Meetings** — general and committee meetings with RSVP, location or online link, add to calendar, attendance and minutes.
• **Committees & people** — see your committees, their work and members, and contact them in one tap.
• **Notifications** — new tasks, announcements, meeting changes and morning reminders.

Light and dark mode. No ads, no tracking.

## URLs
- **Privacy policy:** https://ksa-riyadh.halacreative.com/privacy
- **Account deletion (Play asks for this):** https://ksa-riyadh.halacreative.com/account-deletion
- **Support / marketing URL (Apple):** https://ksa-riyadh.halacreative.com

## Reviewer login (Play "App access" / Apple "App Review Information")
Created on the server with `deploy/manage.sh setup_review_demo` (prints the password;
`--reset` gives a new one). It sees only a sample *Demo Committee* — never real members.

> Sign in with **review@ksa-riyadh.halacreative.com** and the password below. This demo account
> heads a sample committee, so you can see and create tasks, announcements and meetings.
> Real accounts are created by the association's admins (invite codes); there is no public sign-up.

## Apple — App Privacy ("nutrition label")
Data collected, all **linked to the user**, **not used for tracking**, purpose **App Functionality** only:
- Contact Info → **Name**, **Email Address**, **Phone Number**
- User Content → **Other User Content** (tasks, comments, announcements, minutes)
- Identifiers → **User ID**
- Do **not** tick Location, Health, Financial, Browsing, Search, Diagnostics, Usage Data, Purchases.

Export compliance: the app uses only standard HTTPS (declared in the app: no further questions).

## Google Play — Data safety
- Collects data: **Yes**. Shared with third parties: **No**. Encrypted in transit: **Yes**.
  Users can request deletion: **Yes** (in app + the account-deletion URL).
- Personal info → **Name**, **Email address**, **Phone number**: collected, required, purpose *App functionality, Account management*.
- Messages → **Other in-app messages** (announcements, comments): collected, purpose *App functionality*.
- App info and performance / Device or other IDs: **not collected** (the push token is used only to deliver notifications — Google classes it under app functionality; if asked, Device or other IDs → *App functionality*, not shared).

## Google Play — other declarations
- Content rating questionnaire: category **"All other app types"**; answer **No** to violence, sexuality, language, drugs, gambling; user interaction: **Yes, users can communicate** (announcements/comments), **no** sharing of location, **no** purchases → expected rating *Everyone / 3+* with "Users interact".
- Target audience: **18 and over**. Not designed for children.
- Ads: **No**. Government app: **No**. Financial features: **None**. Health: **No**. News app: **No**.

## Graphics (in `mobile/branding/`)
- `icon-512-play.png` — Play icon · `icon-1024.png` — App Store icon (also built into the app)
- `feature-graphic.png` — Play feature graphic 1024×500
- `screenshots/` — 1290×2796 phone screenshots (light and dark), sample data
