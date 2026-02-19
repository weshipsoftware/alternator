# Alternator

A CLI tool for building static websites on your Mac.  
Layouts, includes, and variables in HTML, CSS, and JS.  
Markdown built-in. Localhost server optional.

```shell
USAGE: alternator <source> <target> [--watch] [--port <port>]

ARGUMENTS:
  <source>             Path to your source directory.
  <target>             Path to your target directory.

OPTIONS:
  -w, --watch          Rebiuld <source> as you save changes.
  -p, --port <port>    Serve <target> on localhost:<port>.
  --version            Show the version.
  -h, --help           Show help information.
```

## Documentation

Docs are at: https://weshipsoftware.com/bin/alternator

## Building From Source

### Development

```shell
swift build
```

### Release

```shell
swift build -c release
cp -f .build/release/Alternator /usr/local/bin/alternator
```