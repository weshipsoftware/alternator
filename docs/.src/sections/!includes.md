## Includes

Use an `#include` comment to include another file.

> **Source** _path/to/source/index.html_

```html
---
#layout: !layout.html
---
<!-- #include !header.html -->
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

### Pro Tips

- Included files can have their own layouts.
- `#include` arguments override the included file's metadata:<br />`<!-- #include !file.html #layout: false @foo: bar -->`