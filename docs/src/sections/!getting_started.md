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

`<source>` _changes are automatically rebuilt while the server is running._