# ManyKee.com

ManyKee.com ships two web surfaces in one static distribution:

- `/` briefly introduces ManyKee and the wider ManyMath product family.
- `/web/` is the canonical ManyKee Flutter application.

The older `apps/web` host is a legacy reference and is intentionally not part
of this distribution. The app at `apps/ManyKee` is the current product entry
point for web and native targets.

## Build and verify

From the ManyKee repository root:

```sh
./apps/ManyKee.com/tool/build_web.sh
./apps/ManyKee.com/tool/verify_web_dist.sh
```

The build compiles the KeePassXC WebAssembly worker, builds Flutter with a
`/web/` base href, and assembles the landing page and app at:

```text
apps/ManyKee.com/build/dist
```

To inspect that exact artifact locally:

```sh
python3 -m http.server 8080 --directory apps/ManyKee.com/build/dist
```

Open `http://127.0.0.1:8080/` for the product site or
`http://127.0.0.1:8080/web/` for ManyKee. For a manual Cloudflare Pages
deployment, upload the contents of `apps/ManyKee.com/build/dist`.

The production host must serve `.wasm` files as `application/wasm` and must
not rewrite missing JavaScript or WASM requests to an HTML entry point. The
verification script checks those conditions using a literal static server.

## Source layout

- `site/` contains the semantic HTML, responsive CSS, brand mark, and a current
  screenshot of the canonical ManyKee app.
- `tool/build_web.sh` compiles both the app and its KeePassXC worker before
  composing the deployable distribution.
- `tool/assemble_web_dist.sh` can reassemble an existing Flutter build.
- `tool/verify_web_dist.sh` validates files, paths, content types, and live
  static-server responses.

Building requires Flutter, `wasm-pack`, and the ManyUI repository checked out
beside this repository at `../ManyUI`.
