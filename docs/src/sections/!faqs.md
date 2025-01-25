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

<!--
### How can I support Alternator?

Buy my a coffee.
-->

---