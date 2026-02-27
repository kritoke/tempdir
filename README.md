# tempdir.cr

Creates a temporary directory with atomic mkdtemp/mkstemp support.

## Features

- **Atomic creation**: Uses `mkdtemp` on Unix and `CreateFileA` on Windows for race-free temp directory/file creation
- **Secure permissions**: Directories created with `0o700`, files with `0o600` (owner-only)
- **Cross-platform**: Works on Unix/Linux/macOS and Windows
- **Convenience methods**: `create_tempfile` for atomic tempfile creation inside temp directories
- **Automatic cleanup**: Tempdir removes contents on `#close`, block form auto-cleans

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

### Dir.mktmpdir (block form uses FunctionalTempdir)

```crystal
dir = Dir.mktmpdir(*args)
```

Creates a temporary directory. Arguments are passed to `File.tempname` as-is.
See `File.tempname`.

The returning object is `Tempdir`. It removes all entries when `#close`-d.

With block, the created directory will be removed after block is left. The block form now uses a functional helper under the hood to guarantee cleanup.

```crystal
Dir.mktmpdir do |dir|
  # work with dir
end
```

Functional API
----------------

This library now exposes a small functional-style API via `FunctionalTempdir`.
It keeps resource management explicit and returns Result values for fallible
operations.

Block-style (guaranteed cleanup):

```crystal
FunctionalTempdir.with_tempdir do |path|
  # use path (directory is removed after the block)
end
```

Non-block creation (explicit handle, success wrapped in a Result):

```crystal
res = FunctionalTempdir.create
if res.success?
  info = res.value!
  # info.path is the directory path
  info.close
else
  STDERR.puts res.error!.message
end
```

create_tempfile now returns a `TempdirResult::Result(String, Tempdir::Error)`:

```crystal
res = FunctionalTempdir.create
info = res.value!
file_res = info.create_tempfile("myprefix_")
if file_res.success?
  path = file_res.value!
  # use the file
else
  STDERR.puts file_res.error!.message
end
info.close
```

Migration note
---------------

Existing code that used `Tempdir.new` or `Dir.mktmpdir` can keep working.
`Dir.mktmpdir` still supports the block form and the non-block form now
returns a value-like `FunctionalTempdir::Info` (the non-block `Dir.mktmpdir` will
raise on creation failure). If you prefer non-raising, switch to
`FunctionalTempdir.create` which returns an explicit `Result` you can handle.


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
