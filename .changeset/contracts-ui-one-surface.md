---
'@mj-biz-apps/contracts-ng': patch
---

Three sections, ONE surface for viewing, editing and creating, and a layout that no longer
depends on the window height.

**Create and view are the same place.** A contract being created is a draft whose `ID` is
null — that is the only difference. The outer strip is the family's standard workspace card
(open documents, several agreements side by side); the inner tabs are panes of ONE contract.
Two tabbing systems doing genuinely different jobs, because you cannot close Coverage or add
a seventh pane, so those affordances would be lies.

Each pane carries one of three states — needs-attention / available / not-yet — so the strip
teaches the sequence rather than only reporting it. A disabled pane always says why; a
disabled control with no explanation is the commonest wizard failure.

**Amendments was gated on the wrong thing.** It unlocked when the contract was SAVED, which
is too permissive in the direction that hides itself: saving does not make a term run, so a
saved contract with only Pending terms offered a pane that could do nothing, because both the
composer and `Contracts.AmendTerm` require an ACTIVE term. It now gates on a running term.

**Three real nav items**, from the Application's `DefaultNavItems` and backed by registered
resource classes — an earlier version drew a tab strip inside the page header that looked
identical and was not navigation: no deep links, no resource state, one entry in Explorer's
own nav however many tabs the picture showed.

**Layout.** Page content sat directly inside `mj-left-nav-content`, which forces every direct
child to `display:flex; flex-direction:column; height:100%; overflow:hidden`. Block flow
became a fixed-height flex column that CLIPPED instead of scrolling, so what a page looked
like was a function of the window height. All nine pages now sit in one
`mj-page-body-interior` — MJ's own chrome pattern, excluded from that rule by name. The
workspace page opts into filling explicitly rather than inheriting clipping nobody else wanted.

**Access.** Search is the way into the workspace; the standing roster is gone, because "All
contracts" is the browse surface and repeating it here made the workspace a second, worse
browser. The empty state offers recents (persisted through `UserInfoEngine`, so it follows
the user rather than the browser profile). A contract that cannot be opened now SAYS SO and
refreshes the list — it used to set an error string that nothing rendered, so clicking a
stale row did nothing at all, which is indistinguishable from a dead control.

**Also:** saved rows open through MJ's 4-layer slide-in forms; worklists show contract
numbers and term numbers instead of UUIDs and every row opens its contract; one creation
control per page, in the header, on all nine.
