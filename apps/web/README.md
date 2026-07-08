# apps/web

This is a legacy web host retained as a transitional reference.

The canonical product app is now `apps/ManyKee`, including the web target. Use
the repository-root wrapper when building the product web app:

```bash
scripts/build_manykee_web.sh
```

Do not add new product behavior here. Keep the host only while it remains useful
for comparison or while any remaining web-specific checks are ported into
`apps/ManyKee`, `packages/keepass_web`, or package-level coverage.
