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