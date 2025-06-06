---
#layout: !layout.html
---

```shell
/website $ alternator --help
USAGE: alternator <source> <target> [--watch] [--port <port>]

ARGUMENTS:
  <source>                Path to your source directory.
  <target>                Path to your target directory.

OPTIONS:
  -w, --watch             Rebuild <source> as you save changes.
  -p, --port <port>       Serve <target> on localhost:<port>.
  --version               Show the version.
  -h, --help              Show help information.
```

## Getting Started

Alternator works by reading the files in your `<source>` directory, filling in the
layouts, includes, and variables, then saving the rendered files to your `<target>`
directory for publishing.

```shell
/website $ alternator path/to/source path/to/target
```

Layouts, includes, and variables are defined in text-based `<source>` files using
comments and metadata. More on that later.

Alternator has no directory structure requirements and simply copies the structure
from `<source>` to `<target>`.

### Static Assets

Files that can't be rendered, such as images, are considered static assets and are
copied as-is from `<source>` to `<target>`.

### Ignoring Files

File and directory names starting with a `.` or a `!` are ignored by the build
process. This is useful for a few reasons:

- Dotfiles used for configuration are never touched by Alternator.
- `<source>` files that should _not_ be published, such as layouts and includes, are
  not moved to `<target>`.
- Static assets can live in `<target>` under a `!` directory, such as `!assets/img`,
  instead of being copied during the build process, reducing duplicate files.

### Markdown

Markdown files ending with `.md` are converted to HTML. The rendered files are saved
to `<target>` as `.html` files.

### Watching for Changes

Use the `--watch` flag to monitor `<source>` for changes and automatically render
after each save.

```shell
/website $ alternator path/to/source path/to/target --watch
[watch] watching path/to/source for changes
^c to stop
```

### Localhost Server

Use the `--port` option to serve `<target>` on a localhost server.

```shell
/website $ alternator path/to/source path/to/target --port 8080
[serve] serving path/to/target at http://localhost:8080
^c to stop
```

### Clean URLs

The localhost server supports clean urls.

For example, `<target>/foo.html` is available at `localhost:8080/foo` so you don't
have to clutter your project with extra directories and index files.
Note that not all production servers support this.

### Not Found

If a requested HTML files isn't available, the localhost server will fallback
to `<target>/404.html`.
Note that not all production servers support this.

### Putting It Together

`--watch` and `--port` can be combined for a simple dev environment.

```shell
/website $ alternator path/to/source path/to/target -wp 8080
[watch] watching path/to/source for changes
[serve] serving path/to/target at http://localhost:8080
^c to stop
```

## Layouts

Any file can be used as a _layout_ so long as it has a `#content` comment so specify
where its contents should be rendered.

Ignore layouts by using a `!` to keep them out of `<target>`.

> path/to/source/!layouts/main.html

```html
<!doctype html>
<html>
  <head>
    <title>Alternator</title>
  </head>
  <body>
    <!-- #content -->
  </body>
</html>
```

The `#layout` metadata key defines which layout a file should use. The path to the
layout file is relative to `<source>`.

> path/to/source/index.html

```html
---
#layout: !layouts/main.html
---
<h1>Welcome</h1>
<p>Hello, world!</p>
```

Alternator will render the file inside its layout.

> path/to/target/index.html

```html
<!doctype html>
<html>
  <head>
    <title>Alternator</title>
  </head>
  <body>
    <h1>Welcome</h1>
    <p>Hello, world!</p>
  </body>
</html>
```

## Includes

Files can _include_ other files using an `#include` comment.
The path to the included file is relative to `<source>`.

> path/to/source/app.js

```js
// #include !scripts/foo.js
// #include !scripts/bar.js
```

Like layouts, included files can be kept out of `<target>` with a `!`.

> path/to/source/!scripts/foo.js

```js
function foo() {
  // do something
}
```

> path/to/source/!scripts/bar.js

```js
function bar() {
  // do something else
}
```

Alternator will render the included files in place.

> path/to/target/app.js

```js
function foo() {
  // do something
}
function bar() {
  // do something else
}
```

## Variables

Define _variables_ with an `@` as arguments of an include statement.

> path/to/source/design.css

```css
/* #include !styles/fontFace.css @fontName: Helvetica */
```

And render them as comments.

> path/to/source/!styles/fontFace.css.css

```css
@font-face {
  font-display: swap;
  font-family: /*@fontName*/;
  src: url("/fonts/*@fontName*/.woff2");
}
```

Alternator will render the variables in place.

> path/to/target/design.css

```css
@font-face {
  font-display: swap;
  font-family: Helvetica;
  src: url("/fonts/Helvetica.woff2");
}
```

## Pro Tips

- `.css` and `.js` files from `<source>` will be minified in `<target>`.
- Multiple arguments can be used with an `#include` statement.
- Included files can have their own layouts with a `#layout` argument.<br />
  `<!-- #include !file.html #layout: !layout.html @foo: bar -->`
- You can also pass `#layout: false` to override the metadata layout.
- Variables can define default values in metadata or be given fallback values with
  the `??` operator: `<!-- @foo ?? bar -->`