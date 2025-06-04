---
#layout: !layout.html
---
# Alternator⚡

**al**·**ter**·**na**·**tor**:
A device that converts mechanical energy to electrical energy.

A CLI tool for building static websites on your Mac.
Layouts, includes, and variables in HTML, CSS, and JS.
Markdown built-in. Localhost server optional.

[⤓ Download](!downloads/alternator-2.1.0.pkg) Version 2.1.0

## Getting Started

The alternator command builds your `<source>` files into `<target>`.

<!-- #include !gist.html @id: 979ce70ee106d472a2dbf6b88a8cb378 -->

Add `--watch` to automatically build `<source>` changes on save and
add `--port` to serve `<target>` on localhost.

<!-- #include !gist.html @id: 1e01d425e1d896f5253a1fb3a868b3ea -->

### Pro Tips

- The localhost server uses clean urls.
- File/folder names starting with `!` will not be built to `<target>`.
- Markdown files are automatically converted to HTML files:<br />
  `path/to/source/index.md` → `path/to/target/index.html`
- Layouts, includes, variables, and metadata work in:<br />
  `.css`, `.htm`, `.html`, `.js`, `.md`, `.rss`, `.svg`, `.txt`, and `.xml`.<br />
  All other file types are copied unchanged to `<target>`.
- `<target>/404.html` will be rendered on any request that's not found.

## Layouts

Specify a layout with the `#layout` metadata key.

Any file with a `#content` comment can be used as a layout.

<!-- #include !gist.html @id: 7275044de795bb8cf55ec4f469e59070 -->
<!-- #include !gist.html @id: c3a2b1a96efdb2e9dde22320aa15e6a1 -->
<!-- #include !gist.html @id: ea8a5ee4144ca7aa8ced4e0347a89290 -->

### Pro Tips

- `#layout` and `#include` paths are relative to `<source>`.

## Includes

Use an `#include` comment to include another file.

<!-- #include !gist.html @id: a7dd36bc4c7344bd99a748f1b1311df9 -->
<!-- #include !gist.html @id: b0fd53b3be573001f7db558b88c3ab6f -->
<!-- #include !gist.html @id: a74333b4004271ffcf9c63d3d05b38ae -->
<!-- #include !gist.html @id: 44eca352d4bf967791023d0e98263f9a -->

### Pro Tips

- Included files can have their own layouts.
- `#include` arguments override the included file's metadata:<br />
  `<!-- #include !file.html #layout: false @foo: bar -->`

## Variables

Define variables with `@` symbols and render them in comments.

Assign values in metatdata or as `#include` arguments.

<!-- #include !gist.html @id: 887e91186e538519fbff65a708f8e8e0 -->
<!-- #include !gist.html @id: c312f3d02e27cd2ff360636f40055388 -->
<!-- #include !gist.html @id: 84b2e69f3ac7753d92c2ccac830a34da -->
<!-- #include !gist.html @id: 57ef98102bdfe5049a52a287fc41d9a8 -->

### Pro Tips

- Use `??` to assign a default value: `<!-- @foo ?? bar -->`
- Any comment syntax works:<br />
  `<!-- @foo -->`, `/* @foo */`, or `// @foo`

---

© 🚀 [We Ship Software](https://weshipsoftware.com)