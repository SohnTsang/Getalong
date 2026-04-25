# Monetization Plan

## Recommendation

Use subscriptions first. Avoid aggressive ads in the MVP because ads can damage trust and conversation quality.

## Correct Monetization Model

Getalong should not mainly monetize by limiting how many invites a user can send per day.

The stronger Heymandi-inspired model is:

- Free users can send live invites, but only 1 live outgoing invite at a time.
- Gold users can send 2 live outgoing invites at a time.
- Live acceptance within 15 seconds creates chat and does not consume missed-invite accept quota.
- Missed invite acceptance is limited for free users.
- Paid users can accept missed invites instantly or with higher/no limits.
- Active chat limits can be used as another plan gate.

## Plans

### Free

- Live invite window: 15 seconds
- Concurrent outgoing live invites: 1
- Missed invite accepts: 1/day
- Active chats: 3
- Basic one-time media
- Short video limit

### Silver

- Live invite window: 15 seconds
- Concurrent outgoing live invites: 1
- Missed invite accepts: instant or higher daily limit
- Active chats: 5-10
- 3 Super Invites/day
- No ads if ads are later introduced
- Longer one-time video

### Gold

- Live invite window: 15 seconds
- Concurrent outgoing live invites: 2
- Missed invite accepts: instant or unlimited
- Active chats: unlimited or high cap
- 5 Super Invites/day
- Higher discovery exposure
- Premium profile appearance

## Backend Enforcement

The backend must enforce:
- concurrent live invite slots
- live invite expiry
- missed-invite accept quota
- active chat limits
- super invite limits
- one-time media limits

Never trust client-only subscription state.

## Payment Stack

Choose one:

### Option A: StoreKit 2

Pros:
- direct Apple-native
- no third-party dependency

Cons:
- more backend verification work

### Option B: RevenueCat

Pros:
- easier cross-platform
- useful for Android later
- simpler entitlement management

Cons:
- extra vendor dependency

## Recommendation

Use RevenueCat if Android is definitely planned. Use StoreKit 2 if you want lower dependency and iOS-only first.
