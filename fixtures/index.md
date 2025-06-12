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

> path/to/source/!styles/fontFace.css

```css
@font-face {
  font-display: swap;
  font-family: /* @fontName */;
  src: url("/fonts//* @fontName */.woff2");
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

### Structuring Your Site

Alternator has no directory structure requirements so you can organize `<source>`
however you like.

The structure of `<source>` will be copied to `<target>`.

The structure of `<target>` becomes your URLs when published.

### Keeping `<target>` Clean

When you delete a file from `<source>`, it also gets deleted from `<target>`. There’s
no need to manage source files in `<target>`.

### Managing Dotfiles

Files and directories starting with a `.`, such as `.env`, `.htaccess`, and `.git/`,
are often used for configuration.

Alternator ignores them completely, both in `<source>` and `<target>`.

If they’re in `<source>`, they won’t be moved to `<target>`.

If they’re in `<target>`, they _won’t_ be cleaned up (see above) and the _will_ be
published.

### Ignoring Files

Use a `!` at the beginning of a file or directory name and Alternator will ignore it.

In `<source>` this is useful for files that shouldn’t be copied to `<target>`,
such as `!layout.html` and `!includes/`.

In `<target>` this is useful for files that belong in `<target>` but shouldn’t be
cleaned up after builds, such as `!assets/` and `!img/`.

### Using Markdown

Markdown files (`.md`) are automatically converted to HTML and copied to `<target>`
as `.html` files.

### Multiple _Include_ Arguments

`#include` statements can have multiple arguments, formatted as `key: value` and
separated by spaces:

`// #include sample.js @foo: true @bar: false`

### Fallback _Variable_ Values

Define fallback values for variables with the `??` operator:

`<!-- @foo ?? bar -->`

### _Layout_ Your _Includes_

Included files can have their own layouts, either defined in their metadata or as an
argument passed with the `#include` statement:

`<!-- #include !posts/post.md #layout: !postLayout.html -->`

You can even remove an included file’s layout with `#layout: false`.

### Minifying Assets

`.css` and `.js` files from `<source>` are automatically minified.

### Managing Static Assets

Files that can’t be rendered, such as images, are considered static assets and are
copied as-is from `<source>` to `<target>`.

It’s usually a good idea to put static assets directly in `<target>` under a `!`
directory like `!assets/` or `!images/`.

### Clean URLs

The localhost server supports clean urls.

For example, `<target>/foo.html` is available at `localhost:8080/foo` so you don’t
have to clutter your project with extra directories and index files.

_Not all production servers support this._

### Displaying a _404 Not Found_ Error Page

If the localhost server cannot find a requested file, it will return the
_404 Not Found_ HTTP response status code.

If `<target>/404.html` exists, it will be returned for any not found HTML requests.

No response body will be returned for non-HTML requests.

_Not all production servers support this._

### Publishing Your Site

Alternator sites can be published to any host that serves static files.

This site is hosted on GitHub Pages using _/docs_ as the `<target>`.

Check your web host’s documentation for specifics.