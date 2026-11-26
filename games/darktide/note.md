# Currency and skill-point refunds

**Status (2026-11-26).** Duplicate credit is an unverified hypothesis. Item sales and skill-point refunds are separate cases. There is no evidence here that a skill-point refund changes a currency balance.

The question is whether the backend could apply the same sale or refund twice. After one item is sold, that sale should credit the wallet exactly once. After one spent skill point is refunded, that point should become available exactly once.

An initial permission check answers whether the player may take the action. The client can receive a single confirmation even if the backend also checks ownership, updates the balance, and records the transaction together. Seeing the client request would not establish whether the backend prevents duplicate credit.

The [pinned Darktide 1.13.4 client scripts](external/Darktide-Source-Code/) document the client side. Backend transaction records or an authorized server-side test would be needed to establish that one sale or refund produced two persistent credits.
