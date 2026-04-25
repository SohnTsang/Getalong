# QA Checklist

## Auth

- User can sign up.
- User can sign in.
- User can sign out.
- User can delete account.
- Deleted account cannot appear in feed.
- Banned user cannot post/invite/message.

## Onboarding

- Age gate works.
- Underage user cannot proceed.
- User can create profile.
- User can choose topics.
- Required fields validate.

## Discovery

- User can create post.
- User can see feed.
- Hidden posts do not appear.
- Deleted posts do not appear.
- Posts from blocked users do not appear.
- Pagination works.
- Empty feed state works.

## 15-Second Live Invites

- User can send live invite.
- Live invite shows 15-second countdown.
- Receiver can accept within 15 seconds.
- Receiver can decline.
- Accepted live invite creates chat immediately.
- Accepted live invite does not consume missed-invite accept quota.
- Live invite cannot be accepted after 15 seconds.
- Expired live invite becomes missed.
- Sender's active invite lock is released after accept.
- Sender's active invite lock is released after decline.
- Sender's active invite lock is released after timeout.
- Free/Silver user cannot send second concurrent live invite.
- Gold user can send up to two concurrent live invites.
- Gold user cannot send third concurrent live invite.
- User cannot invite self.
- User cannot invite blocked user.
- Duplicate live invite to same receiver is blocked.
- Banned user cannot send live invite.

## Missed Invites

- Missed invite appears in receiver's missed invite list.
- Free user can accept missed invite within daily limit.
- Free user cannot accept missed invite after limit is reached.
- Paid user can accept missed invite instantly or within plan rules.
- Accepting missed invite creates chat.
- Missed invite cannot be accepted after expiry.
- Accepting missed invite consumes quota only for free users.
- Accepting live invite never consumes missed quota.

## Chat

- Chat list loads.
- Chat room opens.
- Text message sends.
- Realtime receive works.
- Message pagination works.
- Non-participant cannot read messages.
- Block stops future messages.

## One-Time Media

- Image sends.
- GIF sends.
- Video sends.
- Receiver opens once.
- Receiver cannot reopen.
- Sender cannot fake receiver view.
- Third user cannot open.
- Viewed placeholder appears.
- Expired media unavailable.
- Cleanup deletes viewed media.

## Safety

- Report profile works.
- Report post works.
- Report message works.
- Report media works.
- Block user works.
- Blocked user cannot invite/message.
- Active invites between blocked users are cancelled or made unavailable.
- Auto-hide threshold works.

## Subscription

- Free live invite slot limit works.
- Silver live invite slot limit works.
- Gold two-live-invite benefit works.
- Free missed-invite accept quota works.
- Paid missed-invite acceptance works.
- Active chat limits work.
- Backend enforces limits.
- Paywall appears at correct moments.
- Subscription restore works.

## Release

- App does not expose service role key.
- RLS enabled on every table.
- Private media bucket is not public.
- Account deletion works.
- Privacy labels ready.
