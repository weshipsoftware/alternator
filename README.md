# Alternator

A CLI tool for building static websites on your Mac.
Layouts, includes, and variables in HTML, CSS, and JS.
Markdown built-in. Localhost server optional.

## Getting Started

```shell
~/website % alternator --help
USAGE: alternator [<source>] [<target>] [--port <port>]

ARGUMENTS:
  <source>             Path to your source directory. (default: .)
  <target>             Path to your target directory. (default: <source>/_build)

OPTIONS:
  -p, --port <port>    Port for the localhost server.
  --version            Show the version.
  -h, --help           Show help information.
```

The `alternator` command builds your `<source>` files into `<target>`:

```shell
~/website % alternator path/to/source path/to/target
```

Add a `--port` to make `<target>` available on localhost:

```shell
~/website %  alternator path/to/source path/to/target --port 8080
[watch] watching path/to/source for changes
[serve] serving path/to/target on http://localhost:8080
^c to stop
```

`<source>` _changes are automatically rebuilt while the server is running._

## Layouts

Specify a layout with the `#layout` metadata key.

Any file with a `#content` comment can be used as a layout.

> **Source** _path/to/source/index.html_

```html
---
#layout: path/to/source/!layout.html
---
<h1>Welcome</h1>
<p>Hello, world!</p>
```

> **Layout** _path/to/source/!layout.html_

```html
<!DOCTYPE html>
<html>
  <head>
    <title>Alternator</title>
  </head>
  <body>
    <!-- #content -->
  </body>
</html>
```

> **Rendered** _path/to/target/index.html_

```html
<!DOCTYPE html>
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

Use an `#include` comment to include another file.

> **Source** _path/to/source/index.html_

```html
---
#layout: path/to/source/!layout.html
---
<!-- #include path/to/source/!header.html -->
<p>Hello, world!</p>
```

> **Include** _path/to/source/!header.html_

```html
<h1>Welcome</h1>
```

> **Layout** _path/to/source/!layout.html_

```html
<!DOCTYPE html>
<html>
  <head>
    <title>Alternator</title>
  </head>
  <body>
    <!-- #content -->
  </body>
</html>
```

> **Rendered** _path/to/target/index.html_

```html
<!DOCTYPE html>
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

## Variables

Define variables with `@` symbols and render them in comments.

Assign values in metatdata or as `#include` arguments.

> **Source** _path/to/source/index.html_

```html
---
#layout: path/to/source/!layout.html
@siteTitle: Alternator
---
<!-- #include path/to/source/!header.html @pageTitle: Welcome -->
<p>Hello, world!</p>
```

> **Include** _path/to/source/!header.html_

```html
<h1><!-- @pageTitle --></h1>
```

> **Layout** _path/to/source/!layout.html_

```html
<!DOCTYPE html>
<html>
  <head>
    <title><!-- @siteTitle --></title>
  </head>
  <body>
    <!-- #content -->
  </body>
</html>
```

> **Rendered** _path/to/target/index.html_

```html
<!DOCTYPE html>
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

---

### Which file types can I use?

_.css_, _.htm_, _.html_, _.js_, _.md_, _.rss_, _.svg_, _.txt_, and _.xml_.

<p>
  Use the appropriate syntax:
  <code>&lt;!-- @foo --></code>,
  <code>/* @foo */</code>, or
  <code>// @foo</code>
</p>

_Everything else is simply copied from_ `<source>` _to_ `<target>`.

### What about Markdown?

Markdown files are automatically converted to HTML.

`path/to/source/index.md` &rarr; `path/to/target/index.html`

### How do I tell Alternator to ignore certain files?

Any filename starting with `!` will _not_ be built to `<target>`.

_This is especially useful for layouts and included files._

### Can I nest layouts?

Included files can have their own layouts set in metadata.

### How would I override a metadata variable?

`#include` arguments will override the included file's metadata.

`<!-- #include !file.html #layout: false @foo: bar -->`

### Do variables have default values?

You can assign a default value with `??`: `<!-- @foo ?? bar -->`

### Is it possible to capture scope in an included file?

Passing `#closure: true` as an `#include` argument will make all the _including_ file's variables
available in the _included_ file.

### What if I find a bug?

Let me know at: [email@jarrodtaylor.me](mailto:email@jarrodtaylor.me)