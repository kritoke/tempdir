# tempdir.cr

Creates a temporary directory with atomic mkdtemp/mkstemp support.

## Installation

1. Add the dependency to your `shard.yml`:

   ```yaml
   dependencies:
     tempdir:
       github: kritoke/tempdir
   ```

2. Run `shards install`

## Usage

```crystal
require "tempdir"
```

### Dir.mktmpdir

```crystal
dir = Dir.mktmpdir(*args)
```

Creates a temporary directory. Arguments are passed to `File.tempname` as-is.
See `File.tempname`.

The returning object is `Tempdir`. It removes all entries when `#close`-d.

With block, the created directory will be removed after block is left.

```crystal
Dir.mktmpdir do |dir|
  # work with dir
end
```

### Tempdir

The temporary directory class based on `Dir`.

This class only rewrites the `#close` method to remove entries in the
directory.

### create_tempfile

Create a secure tempfile inside the tempdir using atomic `mkstemp`:

```crystal
Dir.mktmpdir do |dir|
  path = dir.create_tempfile("myfile_", data: Slice(UInt8).new([1, 2, 3]))
  # path is the created file path with 0o600 permissions
end
```

The `data` parameter is optional. If provided, writes the bytes atomically.
The file is created with owner-only permissions (0o600) where supported.

### Security

- Directories are created with `0o700` permissions (owner-only).
- Files created via `create_tempfile` use `mkstemp` for atomic creation
  and are set to `0o600` (owner read/write only).
- On Unix, uses `mkdtemp`/`mkstemp` for atomic creation avoiding TOCTOU races.
- On Windows, falls back to `CreateFileA` with `CREATE_NEW` flag for atomic semantics.

## Development

```bash
crystal spec
```

## Contributing

1. Fork it (https://github.com/kritoke/tempdir/fork)
2. Create your feature branch (`git checkout -b my-new-feature`)
3. Commit your changes (`git commit -am 'Add some feature'`)
4. Push to the branch (`git push origin my-new-feature`)
5. Create a new Pull Request

## License

MIT
