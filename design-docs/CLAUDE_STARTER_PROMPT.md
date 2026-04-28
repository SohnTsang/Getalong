# Claude Code Starter Prompt

Use this prompt after placing the documentation pack into your project.

```md
We are building Getalong, an iOS-first SwiftUI + Supabase social discovery app.

Before coding, read:
- CLAUDE.md
- design-docs/PROJECT_PLAN.md
- design-docs/MVP_SCOPE.md
- design-docs/SYSTEM_ARCHITECTURE.md
- design-docs/DATABASE_SCHEMA.md
- design-docs/EDGE_FUNCTIONS.md
- design-docs/ONE_TIME_MEDIA_SECURITY.md
- design-docs/MONETIZATION_PLAN.md
- all files in /agents

Important update:
The invite model is now a 15-second live invitation system.

Rules:
- A live invite lasts 15 seconds.
- If accepted within 15 seconds, chat is created immediately.
- Live acceptance does not consume missed-invite accept quota.
- If not accepted within 15 seconds, the invite becomes missed.
- Free/Silver users can have 1 outgoing live invite active at a time.
- Gold users can have 2 outgoing live invites active at a time.
- Free users have limited missed-invite accepts per day.
- Paid users can accept missed invites instantly or with higher/no limits.
- Do not implement the main invite model as simple daily sent-invite limits.

Your first task:
1. Create the initial Supabase migration for the database schema in design-docs/DATABASE_SCHEMA.md.
2. Enable RLS on every table.
3. Add safe starter RLS policies.
4. Create the iOS SwiftUI project shell structure.
5. Create tabs: Discover, Invites, Chats, Profile.
6. Create placeholder services and models.
7. Include placeholder invite services for sendLiveInvite, acceptLiveInvite, markLiveInviteMissed, acceptMissedInvite, and cancelLiveInvite.
8. Do not implement Android yet.
9. Do not build group chat, video calls, AI matching, or full admin dashboard.

Rules:
- Use Getalong as the app name.
- Keep code modular.
- Do not expose service role key.
- Do not make chat media public.
- One-time media must be server-enforced later through Edge Functions.
- Invite locks and missed-invite quotas must be server-enforced through Edge Functions.
- After coding, summarize files changed and how to test.
```
