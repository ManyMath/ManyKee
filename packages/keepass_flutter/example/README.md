# keepass_flutter example

This package is the canonical reference GUI for the `keepass_flutter` plugin in the ManyKee workspace.

## Purpose

Use this example to verify the supported native Flutter surface locally:

- unlock and re-unlock flows
- vault browsing and search
- entry and group CRUD plus save/reload continuity
- settings behavior and stub-provider rows

The example intentionally consumes `package:keepass_flutter` as a downstream app would. It is the primary GUI proof surface for v1.5.

## Repo position

- Primary Flutter surfaces: `packages/keepass_flutter` and this example package
- Secondary/transitional host: `apps/native`

The milestone goal is to keep reusable integration and reference-GUI proof centered in the package workspace rather than in standalone app shells.
