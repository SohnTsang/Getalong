# Getalong 15-Second Live Invite Update

This replacement pack updates the Getalong documentation and agent instructions to use the corrected Heymandi-inspired invite model:

- Live invite window: 15 seconds
- Free/Silver users: 1 concurrent outgoing live invite
- Gold users: 2 concurrent outgoing live invites
- Live accept creates chat immediately
- Live accept does not consume missed-invite accept quota
- If not accepted within 15 seconds, invite becomes a missed invite
- Free users have limited missed-invite accepts per day
- Paid users can accept missed invites instantly or with higher/no limits

## How to Apply

Copy these files into your existing Getalong project root and replace files with the same paths.

Recommended command:

```bash
unzip getalong_15s_invite_md_replacements.zip -d /path/to/getalong-project
```

Then ask Claude Code:

```md
Please reread CLAUDE.md, design-docs/MVP_SCOPE.md, design-docs/DATABASE_SCHEMA.md, design-docs/EDGE_FUNCTIONS.md, design-docs/MONETIZATION_PLAN.md, and the updated agent files. The invite model has changed to a 15-second live invitation system. Update any implementation plans, schema, Edge Function contracts, and tests to follow this model. Do not use daily sent-invite limits as the main mechanic.
```
