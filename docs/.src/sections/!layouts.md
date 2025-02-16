## Layouts

Specify a layout with the `#layout` metadata key.

Any file with a `#content` comment can be used as a layout.

> **Source** _path/to/source/index.html_

```html
---
#layout: !layout.html
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

### Pro Tips

- `#layout` and `#include` paths are relative to `<source>`.