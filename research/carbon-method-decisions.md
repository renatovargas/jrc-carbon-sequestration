# Method decisions

The reference method is Vallecillo et al. (2019), cited as Part II, and its update in La Notte et al. (2021), cited as Part III. They break ties. Page numbers are PDF page indices.

| Topic | Reference | Decision here | Verification |
|---|---|---|---|
| Offset | Part III pp. 110 to 112 and 118 define the flow as removals minus emissions over all ecosystem types at EU level. The Eurostat handbook pp. 145 to 148 reports signed balances by type. | Offset at EU level. Signed balances are kept in the tables. | Verified in text |
| Allocation to countries | Part III p. 112, Equation 6.1: the share of each country in the forest removals, times total removals minus total emissions. | As in Part III. An earlier version used the net annual increment of forest. The comparison was run once and is kept in `data/outputs/report/allocation_comparison.rds`. With the forest share no country has a negative missed flow, and a country whose forest is a net source receives no flow. | Verified in text |
| Harvested wood products | Parts II and III do not deduct them, and their carbon chapters do not mention them. Handbook para 9.56, p. 156, keeps them out of net sequestration, as a separate category. | Not deducted, and shown as a memo item. An earlier version deducted the sink from forest removals. The comparison is in the same table. | Verified in text |
| Flow without offset and missed flow | Part III pp. 110 and 118, removals before emissions, against the flow after them. | Flow without offset is the sum of removals of the six land categories. Missed flow is that flow minus the actual flow, which adds up to the EU emissions. | Verified in text, definition of missed flow inferred |
| Maps | Part II pp. 49 and 50 map forest land only, because other types switch between source and sink. | The actual flow and its value, and the removals of forest land as the map of the flow without offset. The missed flow is in tables only. | Verified in text |
| Unit | Handbook paras 9.48 and 9.57 give the sign reversal and 12/44. | CO2 in thousand tonnes, carbon at 12/44. | Verified in text |
| Other land | Inventory category CRF4F. | Kept as one category. | Verified in text |
| Spatial key | Part II p. 50 and Annex 7 use productivity on forest classes 311, 312, 313 and 324. JRC142634 pp. 9, 17 and 18 names Gross Dry Matter Productivity (GDMP) as the proxy. | Forest share of each cell from the accounting layer, times annual GDMP of the same year (1 km v2 for 2000, 2006 and 2012, 300 m v2 for 2018 and 2024). | Verified in text |
| Land cover | JRC142634 Table 1, p. 7, names the accounting layers. The EEA published version 21 in September 2026, so one product covers all five years. | Accounting layers 2000, 2006, 2012, 2018 and 2024. | Verified in text and online |
| Price | Part II pp. 60 and 61 and Part III p. 113 use EUR 30 per tonne of CO2, as a reference point. | Social cost of carbon, EUR 343.6 per tonne of C in 2023 euros (EUR 93.7 per tonne of CO2), constant in real terms. See `research/carbon-price.md`. Part III's price is shown for comparison. | Verified in text |
