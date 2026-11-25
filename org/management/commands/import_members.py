"""One-time import of the unit's members from the owner's Excel sheet (run on the server only).

    deploy/manage.sh import_members /path/to/sheet.xlsx --dry-run     # check, prints counts only
    deploy/manage.sh import_members /path/to/sheet.xlsx               # import

Expected sheet "Members", header row with: Name, Mobile No., Unit Place, Member Type, Wing,
Position 1, Position 2, Comments (other columns are ignored; header cells may have a second line).

- Everyone is created as a member who **can't sign in yet** (no password, no invite sent). Admins
  send invite codes later from People. Nobody is made admin or super admin.
- Wing "EXIT" (left Saudi Arabia) rows are skipped.
- Wing cells are mapped to the unit's wings with WING_MAP; unknown wing text stops the import
  (use --map "RAW TEXT=Wing A,Wing B" to add a mapping, or fix the sheet).
- Position 1 belongs to the first wing, Position 2 to the second. President / Secretary /
  Treasurer etc. are unit-level designations (stored as the person's designation).
- Comments become private admin notes and set "needs follow-up".
- People whose mobile number is already in the app are skipped (reported).
Prints only counts and wing/position names: never names or phone numbers.
"""

import re
import secrets

from django.contrib.auth.models import User
from django.core.management.base import BaseCommand, CommandError
from django.db import transaction

from org.models import Committee, Member, Membership, phone_digits

WINGS = ["Youth", "Dawa", "QHLS", "Finance", "Media / Social Media", "Education", "Umrah", "ORG",
         "Social Welfare", "Career & Sports"]
WING_MAP = {
    "YOUTH": ["Youth"], "DAWA": ["Dawa"], "QHLS": ["QHLS"], "FINANCE": ["Finance"], "UMRAH": ["Umrah"],
    "MEDIA": ["Media / Social Media"], "SOCIAL MEDIA": ["Media / Social Media"],
    "SOCIAL MEDAI ,PRO": ["Media / Social Media"], "SOCIAL MEDIA,PRO": ["Media / Social Media"],
    "SOCIAL WELFARE": ["Social Welfare"], "ORG": ["ORG"], "EDUCATION": ["Education"],
    "CAREER & SPORTS": ["Career & Sports"], "ORG,CAREER & SPORTS": ["ORG", "Career & Sports"],
    "ORG,EDUCATION": ["ORG", "Education"], "EDUCATION & PUBLICITY": ["Education"],
    "SOCIAL MEDIA & UMRAH": ["Media / Social Media", "Umrah"],
}
SKIP_WINGS = {"EXIT"}
UNIT_TITLES = {"PRESIDENT": "President", "VICE PRESIDENT": "Vice President", "SECRETARY": "Secretary",
               "JOINT SECRETARY": "Joint Secretary", "TREASURER": "Treasurer"}
COLORS = ["teal", "blue", "indigo", "purple", "pink", "red", "orange", "amber", "green", "gray"]


def clean(v):
    return re.sub(r"\s+", " ", str(v)).strip() if v not in (None, "") else ""


def nice(v):
    """'MALAZ AREA' -> 'Malaz Area', keeps short acronyms like QHLS / ORG."""
    return " ".join(w if (len(w) <= 4 and w.isupper() and w not in ("AREA", "ABC")) else w.capitalize()
                    for w in clean(v).split(" "))


class Command(BaseCommand):
    help = "Import members from the owner's Excel sheet (one time). Prints counts only."

    def add_arguments(self, parser):
        parser.add_argument("xlsx")
        parser.add_argument("--sheet", default="Members")
        parser.add_argument("--dry-run", action="store_true")
        parser.add_argument("--map", action="append", default=[], help='"RAW WING TEXT=Wing A,Wing B"')

    def handle(self, *args, **o):
        try:
            import openpyxl
        except ImportError:
            raise CommandError("openpyxl is needed: .venv/bin/pip install openpyxl")
        wing_map = dict(WING_MAP)
        for m in o["map"]:
            raw, _, to = m.partition("=")
            wing_map[clean(raw).upper()] = [w.strip() for w in to.split(",") if w.strip()]

        wb = openpyxl.load_workbook(o["xlsx"], data_only=True, read_only=True)
        if o["sheet"] not in wb.sheetnames:
            raise CommandError(f"No sheet named {o['sheet']!r}. Sheets: {wb.sheetnames}")
        rows = list(wb[o["sheet"]].iter_rows(values_only=True))
        hi = next((i for i, r in enumerate(rows[:20]) if any(clean(c).lower().startswith("name") for c in r)), None)
        if hi is None:
            raise CommandError("Couldn't find the header row (a cell starting with 'Name').")
        header = [clean(c).split(" ")[0].lower() if c else "" for c in rows[hi]]
        full = [clean(c).lower() for c in rows[hi]]

        def col(*starts):
            for i, h in enumerate(full):
                if any(h.startswith(s) for s in starts):
                    return i
            return None

        ci = {k: col(*v) for k, v in {
            "name": ["name"], "phone": ["mobile", "phone"], "place": ["unit place"], "type": ["member type"],
            "wing": ["wing"], "pos1": ["position 1"], "pos2": ["position 2"], "comments": ["comment"],
        }.items()}
        if ci["name"] is None:
            raise CommandError(f"Missing Name column. Header: {header}")

        def get(r, k):
            i = ci[k]
            return clean(r[i]) if i is not None and i < len(r) else ""

        data = [r for r in rows[hi + 1:] if get(r, "name")]
        unknown = sorted({get(r, "wing").upper() for r in data
                          if get(r, "wing") and get(r, "wing").upper() not in wing_map
                          and get(r, "wing").upper() not in SKIP_WINGS})
        if unknown:
            raise CommandError("Unknown wing text (add --map or fix the sheet): " + "; ".join(unknown)
                               + f"\nKnown wings: {', '.join(WINGS)}")

        stats = {"created": 0, "skipped_exit": 0, "skipped_duplicate_phone": 0, "no_phone": 0,
                 "executives": 0, "with_notes": 0}
        positions = {}
        with transaction.atomic():
            wings = {}
            for i, name in enumerate(WINGS):
                c = Committee.objects.filter(name__iexact=name).first()
                if not c:
                    c = Committee.objects.create(name=name, color=COLORS[i % len(COLORS)], order=10 + i)
                wings[name] = c
            seen = set()
            for r in data:
                wing_text = get(r, "wing").upper()
                if wing_text in SKIP_WINGS:
                    stats["skipped_exit"] += 1
                    continue
                phone = get(r, "phone")
                key = phone_digits(phone)
                if key and (key in seen or Member.objects.filter(phone_key=key).exists()):
                    stats["skipped_duplicate_phone"] += 1
                    continue
                if key:
                    seen.add(key)
                else:
                    stats["no_phone"] += 1
                my_wings = wing_map.get(wing_text, []) if wing_text else []
                titles, wing_pos = [], {}
                for idx, pk in enumerate(("pos1", "pos2")):
                    pos = get(r, pk)
                    if not pos:
                        continue
                    if pos.upper() in UNIT_TITLES:
                        titles.append(UNIT_TITLES[pos.upper()])
                    elif idx < len(my_wings):
                        wing_pos[my_wings[idx]] = nice(pos)
                    elif my_wings:
                        wing_pos.setdefault(my_wings[0], nice(pos))
                    else:
                        titles.append(nice(pos))
                    positions[nice(pos)] = positions.get(nice(pos), 0) + 1
                user = User(username=f"p{key}" if key and not User.objects.filter(username=f"p{key}").exists()
                            else f"m-{secrets.token_hex(5)}", first_name=get(r, "name")[:150])
                user.set_unusable_password()
                user.save()
                m = user.member
                m.name = get(r, "name")[:120]
                m.phone = phone[:30]
                m.title = ", ".join(dict.fromkeys(titles))[:80]
                m.unit_place = nice(get(r, "place"))[:60]
                m.member_type = Member.EXECUTIVE if get(r, "type").upper().startswith("EXEC") else Member.MEMBER
                m.notes = get(r, "comments")
                m.needs_followup = bool(m.notes)
                m.save()
                for w in my_wings:
                    Membership.objects.get_or_create(member=m, committee=wings[w],
                                                     defaults={"position": wing_pos.get(w, "")})
                stats["created"] += 1
                stats["executives"] += m.member_type == Member.EXECUTIVE
                stats["with_notes"] += bool(m.notes)
            if o["dry_run"]:
                transaction.set_rollback(True)

        self.stdout.write(("DRY RUN (nothing saved): " if o["dry_run"] else "Imported: ") + ", ".join(
            f"{k.replace('_', ' ')} {v}" for k, v in stats.items()))
        self.stdout.write("Positions seen: " + ", ".join(f"{k} ×{v}" for k, v in sorted(positions.items())))
        self.stdout.write("Nobody can sign in yet: send invite codes from People in the app.")
