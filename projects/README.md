# Projects

Each subdirectory is one deployment's **documentation and configuration**.

A complete, working application = the `../product/` folder + one project folder
from here. Projects hold no generic product code; they provide configuration,
deployment documentation, and the deployment-specific sidecar.

## Deployments

- [`sauna/`](sauna/README.md): sauna booking for a homeowner association.

## UI mockups

Deployment folders may include supplied UI mockups as visual references (for
example `projects/sauna/docs/mocks/`). When mockups exist, frontend work for
that deployment should follow them for layout, styling, coloring, spacing,
typography, and component states while using the fixed frontend stack
(**React 18, TypeScript, Vite, React Router, Chakra UI v2**) and the generic
frontend conventions in [`../product/frontend-solid/AGENTS.md`](../product/frontend-solid/AGENTS.md). Keep
deployment-specific branding/assets in the deployment folder and reusable
patterns in the generic product where appropriate.
