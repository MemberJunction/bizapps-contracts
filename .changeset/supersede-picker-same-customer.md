---
'@mj-biz-apps/contracts-core-entities-server': patch
'@mj-biz-apps/contracts-ng': patch
---

The re-papering picker now offers only contracts for the same customer, and says why when it offers nothing (#28 items 2, 3 and 4). Eligibility was same-level, unsuperseded and not-this-contract; a predecessor must also belong to the same customer, since re-papering replaces one customer's agreement with a later agreement for that customer. `ContractEntityServer` gains a matching `refuseCrossCustomerSupersession`, because the picker decides what to offer and only the entity tier governs every other writer of the FK — a generated form, an import, another app.

Options read `<ContractNumber> — <Description>`, falling back to the contract type when there is no description; the number alone identified nothing when choosing between several. The two explanatory paragraphs under the Link button are gone — an empty list now reads "No eligible contracts" in the combobox itself, where a person actually looks. The panel is built from the kit's `.mjc-fields` / `.mjc-field` markup instead of MJ's `mj-forms-field`, so the "Supersedes" label matches the Dates and Renewal terms labels rather than sitting beside them in a different size and case.
