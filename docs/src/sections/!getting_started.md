## Getting Started

```shell
~/website % alternator --help
USAGE: alternator <source> <target> [--port <port>]

ARGUMENTS:
  <source>                Path to your source directory.
  <target>                Path to your target directory.

OPTIONS:
  -p, --port <port>       Port for the localhost server.
  --version               Show the version.
  -h, --help              Show help information.
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

### Pro Tips

- `<source>` changes auto-build while the server is running.
- Files whose names start with `!` will _not_ be written to `<target>`.
- Markdown files are automatically converted to HTML files:<br />
  `path/to/source/index.md` &rarr; `path/to/target/index.html`
- Layouts, includes, variables, and metadata work in:
  <br />
  _.css_, _.htm_, _.html_, _.js_, _.md_, _.rss_, _.svg_, _.txt_, and _.xml_.
  <br />
  All other file types are copied unchanged to `<target>`.
- Dotfiles are completely ignored.