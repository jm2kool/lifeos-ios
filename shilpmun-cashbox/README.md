# SHILPMUN 2026 · Coupon & Cash Desk

A one-page tracker for the coupon desk: every coupon sale (₹50 each), the change handed back, refunds, and cash put in or taken out of the box.

- **Sale:** pick the coupon count, tap the notes you're handed, and it tells you the exact change to give back (with which notes).
- **UPI:** logged as a sale but kept out of the cash-box total.
- **Cash in/out:** starting change, or cash handed to the treasurer.
- **Count the box:** enter how many of each note you have and it checks the count against the log.
- **Void, never delete:** mistakes are struck out but stay in the log. Each new entry can be undone for a few seconds after you record it.
- **Export CSV** for handing the record over.

The log lives in a Supabase database behind a desk PIN. The PIN is checked on the server and is not stored in this repository. Amounts are worked out on the server from the coupon count, so the page can't record a wrong total.
