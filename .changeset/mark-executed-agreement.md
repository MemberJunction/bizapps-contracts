---
'@mj-biz-apps/contracts-ng': patch
'@mj-biz-apps/contracts-entities': patch
---

Contract form: mark a linked file as the executed agreement (golive #213, item 1).

Since contracts #36 (golive #203 item 16), `vwContracts.IsAwaitingDocument` clears only when a file
linked to the contract carries the `Executed Agreement` file category — but MJ's stock Attachments
panel at 6.1.0-edge.4 has no way to set a file's category, so a contract whose type requires an
executed document read **Awaiting document** no matter what was attached.

A new **Executed agreement** field panel on the Contract form lists the files linked to the contract
with their category and offers **Mark as executed agreement** / **Unmark** per file. Mark sets the
file's `CategoryID` to the `MJ: File Categories` row named `Executed Agreement`, looked up by name
(the same way the view resolves it); Unmark clears it. After either write the form reloads the
record, so the header chip and the Overview health line follow the database rather than the panel's
opinion. A refresh control on the panel reloads the list, because attaching a file through the
toolbar's Attachments panel does not otherwise reach it.

The panel follows the Re-papering rule: always visible, and while the form is editing or the contract
is unsaved it shows the list read-only with **Finish editing to change** / **Save this contract
first** in place of the buttons. It hides the buttons and says why when the user lacks update
permission on `MJ: Files`, and it says plainly when the `Executed Agreement` category row is missing
from the database rather than failing silently.

The category name now has one spelling in code — `EXECUTED_AGREEMENT_FILE_CATEGORY` in
`@mj-biz-apps/contracts-entities` — and a test pins it to the migration's seed. No schema, migration
or metadata change. Attaching files, removing them and opening them stay with MJ's stock Attachments
panel; the upload-time checkbox and a category picker in its Edit Details are MJ gaps and are not
addressed here.
