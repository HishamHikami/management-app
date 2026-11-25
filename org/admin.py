from django.contrib import admin

from .models import (
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
    Grant,
    Program,
    ProgramResource,
    PublicPost,
    PasswordResetRequest,
    Responsibility,
    ResponsibilityDone,
    Receipt,
    Task,
    TaskUpdate,
)


class MembershipInline(admin.TabularInline):
    model = Membership
    extra = 0
    autocomplete_fields = ["member"]


@admin.register(Member)
class MemberAdmin(admin.ModelAdmin):
    list_display = ["name", "phone", "title", "member_type", "level", "unit_place", "active"]
    search_fields = ["name", "phone", "user__email"]
    list_filter = ["member_type", "level", "is_public", "needs_followup", "memberships__committee"]
    raw_id_fields = ["user"]

    @admin.display(boolean=True)
    def active(self, obj):
        return obj.user.is_active


@admin.register(Committee)
class CommitteeAdmin(admin.ModelAdmin):
    list_display = ["name", "is_core", "color", "order", "archived"]
    list_editable = ["order"]
    inlines = [MembershipInline]


class TaskUpdateInline(admin.TabularInline):
    model = TaskUpdate
    extra = 0
    readonly_fields = ["author", "kind", "from_value", "to_value", "created_at"]


@admin.register(Task)
class TaskAdmin(admin.ModelAdmin):
    list_display = ["title", "committee", "status", "priority", "due_date", "created_by"]
    list_filter = ["status", "priority", "committee"]
    search_fields = ["title", "description"]
    filter_horizontal = ["assignees"]
    inlines = [TaskUpdateInline]


@admin.register(Announcement)
class AnnouncementAdmin(admin.ModelAdmin):
    list_display = ["title", "author", "audience", "pinned", "urgent", "requires_ack", "created_at"]
    list_filter = ["audience", "pinned", "urgent"]
    search_fields = ["title", "body"]


class AttendeeInline(admin.TabularInline):
    model = Attendee
    extra = 0


@admin.register(Meeting)
class MeetingAdmin(admin.ModelAdmin):
    list_display = ["title", "committee", "start", "status"]
    list_filter = ["status", "committee"]
    inlines = [AttendeeInline]


@admin.register(Invite)
class InviteAdmin(admin.ModelAdmin):
    list_display = ["member", "created_by", "created_at", "expires_at", "used_at"]
    readonly_fields = ["code_hash"]


@admin.register(ApiToken)
class ApiTokenAdmin(admin.ModelAdmin):
    list_display = ["user", "device", "created_at", "last_used_at"]
    readonly_fields = ["key_hash"]


admin.site.register([Receipt, Notification, Device])

admin.site.register([Grant, Program, ProgramResource, PublicPost, PasswordResetRequest, Responsibility, ResponsibilityDone])
