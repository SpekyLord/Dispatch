# Category Selection

## Phase 1: Manual Selection

In Phase 1, citizens must manually select an incident category when submitting a report. There is no auto-categorization.

The 7 canonical categories are:

| Category | Label | Typical Use |
|---|---|---|
| `fire` | Fire | Building fires, wildfires, vehicle fires |
| `flood` | Flood | Flash floods, rising water levels |
| `earthquake` | Earthquake | Seismic events, aftershocks |
| `road_accident` | Road Accident | Vehicle collisions, road hazards |
| `medical` | Medical Emergency | Medical emergencies, injuries |
| `structural` | Structural Damage | Building collapse, infrastructure damage |
| `other` | Other | Anything not covered above |

## Phase 2: Rule-Based Auto-Categorization

Phase 2 introduces keyword-based auto-categorization using English and Filipino trigger words from the report description. When auto-categorization is active:

- The system suggests a category based on description text
- **The manual selector remains as an override** — the citizen can always change the suggested category
- The final stored category is whatever the citizen confirms, not the system suggestion

## Phase 5: ML Classification (Stretch)

Phase 5 may introduce:
- ML-enhanced text classification with confidence scoring
- Image-based classification as a supplementary signal
- Safe fallback to rule-based when ML confidence is low

Manual override is preserved in all phases. The citizen always has the final say on category.

## Canonical Enum

The `report_category` enum is shared across all phases and should not be modified without a product decision:

```
fire | flood | earthquake | road_accident | medical | structural | other
```
