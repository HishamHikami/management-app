"""Daily reminders (run by a systemd timer each morning):
- meetings in the next 24 hours, to everyone invited who hasn't declined;
- tasks due today or tomorrow, to their assignees.
"""

from datetime import timedelta

from django.core.management.base import BaseCommand
from django.utils import timezone

from org.models import Attendee, Meeting, Task
from org.services import notify, task_watchers


class Command(BaseCommand):
    help = "Send meeting and due-date reminders."

    def handle(self, *args, **o):
        now = timezone.now()
        sent = 0
        for m in Meeting.objects.filter(
            status=Meeting.SCHEDULED, reminded=False, start__gte=now, start__lte=now + timedelta(hours=24)
        ):
            people = [a.member for a in m.attendees.select_related("member__user")
                      .exclude(rsvp=Attendee.DECLINED) if a.member.active]
            when = timezone.localtime(m.start).strftime("%a %H:%M")
            notify(people, "meeting", m.pk, f"Reminder: {m.title}", f"{when}" + (f" · {m.location}" if m.location else ""))
            m.reminded = True
            m.save(update_fields=["reminded"])
            sent += len(people)

        today = timezone.localdate()
        for t in Task.objects.exclude(status__in=Task.CLOSED).filter(due_date__in=[today, today + timedelta(days=1)]):
            people = list(t.assignees.filter(user__is_active=True)) or task_watchers(t)
            label = "today" if t.due_date == today else "tomorrow"
            notify(people, "task", t.pk, f"Due {label}: {t.title}", t.committee.name)
            sent += len(people)
        self.stdout.write(f"Reminders sent: {sent}")
