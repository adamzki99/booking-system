---
name: ui-mockup-alignment
description: Follow supplied UI mockups and design references for layout, styling, coloring, spacing, typography, and component states while keeping the repository's fixed frontend stack (React 18, TypeScript, Vite, React Router, Chakra UI v2). Use when implementing or changing frontend UI in this repo, especially when mockups are provided.
---

# UI Mockup Alignment

Use this skill when building or changing UI in this repository and mockups or design references exist.

## Fixed stack (do not replace)

- **React 18**
- **TypeScript**
- **Vite**
- **React Router**
- **Chakra UI v2**

Do not introduce a different UI framework, styling system, router, bundler, or language stack for generic frontend work. Implement mockup intent with the existing stack.

## Source of truth for visual work

1. **Supplied mockups and design references**: when mockups are provided for the relevant flow or deployment, treat them as the visual source of truth for layout, hierarchy, spacing, coloring, typography, radii, iconography cues, component states, and responsive behavior.
2. **Existing generic implementation**: align with `product/frontend/src/theme.ts`, Chakra component recipes/tokens, and established frontend patterns in `product/frontend/`.
3. **Deployment boundaries**: keep deployment-specific branding, copy, and assets in `projects/<name>/`; extract reusable visual patterns into generic theme tokens/components only when they are useful across deployments.

For the sauna deployment, canonical normal-user mockups live at:
- `projects/sauna/docs/mocks/sauna_booking_website_normal_user_mock_desktop.html`
- `projects/sauna/docs/mocks/sauna_booking_website_normal_user_mock_mobile.html`

## How to align with mockups

- Match the mockup's structure and intent: page shell/app chrome, navigation patterns, headings, cards/sections, tables/lists, forms, actions, empty/loading/error states, and per-item controls as shown.
- Match visual treatment: warm palette and contrast, surface/background separation, borders, shadows (or lack of them), spacing rhythm, alignment, typography scale/weight, control sizing, and interaction states (hover, focus, selected, disabled) consistent with the mockup.
- Prefer **Chakra primitives, theme tokens, semantic tokens, and component variants/recipes** over bespoke CSS. Use custom CSS only when Chakra cannot express the requirement (accessibility, missing capability, or performance), and keep it minimal and documented.
- Reuse or extend existing tokens/recipes in `product/frontend/src/theme.ts` before adding one-off styles. When a mockup introduces a reusable pattern, encode it in theme/tokens/variants rather than duplicating hex values or ad-hoc spacing in pages.
- Preserve the product's warm base design language reflected in the current theme unless a supplied mockup intentionally defines a change: Inter typography, accent `#9A2F22` / hover `#7A241A` / tint `#F6E6E0`, warm ink/muted/line/canvas/subtle/hover/surface colors, card and control radii, and ~44px interactive control heights.
- Keep implementations responsive and accessible; follow the mockup's desktop/mobile intent where provided.

## What not to do

- Do not invent a conflicting visual direction when a relevant mockup exists.
- Do not "improve" away mockup styling, colors, spacing, or hierarchy unless the user asks or the mockup is clearly incompatible with accessibility/technical constraints (if so, explain the deviation).
- Do not hardcode deployment-specific branding in generic product code.
- Do not replace Chakra UI v2 patterns with raw CSS frameworks or a different component library.
- Do not break API contracts, routing structure, or existing behavior without updating related code and tests.

## Verification

- Compare the implemented UI against the supplied mockup(s) for the affected screens/states.
- Run relevant frontend checks from `product/frontend/` (`npm test`, `npm run build`) when feasible.
- When mockup content cannot be fully inspected from bundled artifacts, state what was inferred and what remains unverified.
