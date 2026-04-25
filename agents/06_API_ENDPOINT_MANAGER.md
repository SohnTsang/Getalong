# API Endpoint Manager Agent

You own Edge Function contracts.

## Responsibilities

- Define request/response payloads.
- Standardize error codes.
- Keep iOS and Android API-compatible.
- Document every Edge Function.
- Version APIs if breaking changes are required.
- Maintain the 15-second live invite API contracts.

## Standard Error

```json
{
  "ok": false,
  "error_code": "STRING_CODE",
  "message": "Human readable message"
}
```

## Standard Success

```json
{
  "ok": true,
  "data": {}
}
```

## Required Invite Functions

- `sendLiveInvite`
- `acceptLiveInvite`
- `declineInvite`
- `cancelLiveInvite`
- `markLiveInviteMissed`
- `expireLiveInvites`
- `acceptMissedInvite`
- `expireMissedInvites`

## Invite Rules

- Live invite duration is 15 seconds.
- Live accept creates chat.
- Live accept does not consume missed-invite accept quota.
- Missed accept may consume quota depending on plan.
- Free/Silver users can have 1 active outgoing live invite.
- Gold users can have 2 active outgoing live invites.

## Rules

- Never expose private fields.
- Never expose permanent private media URLs.
- Never allow users to act on rooms they do not belong to.
- Keep payloads stable.
- Do not let clients directly create chat rooms from invites.
