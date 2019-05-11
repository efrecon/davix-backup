# davix backup

`davix-backup` will select the lastest file matching a pattern (probably the
result of a local backup operation), possibly compress it and send it to a
remote resource for long(er)-term storage. `davix-backup` is able to rotate the
files at the remote location to keep their number under a given threshold.
`davix-backup` assumes that it "owns" the remote directory and will only work
properly when a single `davix-backup` (possibly run several times) is run
against a remote directory. While the default is to use the underlying [davix]
utilities for backup operations, this can be turned off to perform backup
against local (mounted?) directories.

  [davix]: https://davix.web.cern.ch/davix/docs/devel/

## Options

`davix-backup` accepts both short (led by a single `-` dash sign) and long (led
by two `--` dash sign) options. Long options can either be separated from their
arguments with a space or an equal `=` sign.

Apart from the following options, `davix-backup` accepts one or several patterns
as argument, and these patterns will be used when looking for the latest file to
select for backup. For the cases when the patterns are led by a `-` dash sign,
it is possible to separate the options from the pattern arguments with a
double-dash, `--`.

### `-v` or `--verbose`

This option does not take any argument and will output more messages on the
console. This can be usefull for following up progress and/or in logs of
long-going backup procedures.

### `-x` or `--davix`

Takes the start of the `davix` commands to execute as an argument and defaults
to `davix`. The `davix` utilities come as a set of binaries where specific
operations are appended to the main name after a single dash, e.g. `davix-ls` or
`davix-mkdir`. `davix-backup` will automatically add the necessary sub-command
to the command specified through its `--davix` option. When the value of this
option is empty, `davix` support will be turned off and `davix-backup` will work
against local directories.

If you do not want or cannot install `davix`, but have a Docker environment, it
is possible to give the following as a command, with no trailing space. This
will only work when working uncompressed, as compression uses a temporary file
that is likely to be created outside of your home directory.

```shell
docker run -it --rm --entrypoint= -v ${HOME}:${HOME} efrecon/davix davix
```

### `-o` or `--davix-options`

Takes a string that might contain `davix` specific options that will be added to
the options given to all `davix` commands before their execution. The default
set of `davix` options is an empty string. The long option can also be written
`--davix-opts`.

This option is cumulative (together with the next one), every occurence of the
option will append the value to the set of options that will be passed to
`davix` with a whitespace separator.

### `-O` or `--davix-options-file`

Takes the path to a file that might contain `davix` specific options that will
be added to the options given to all `davix` commands before their execution.
This is a good place to specify credentials of various sorts, for example. The
default is an empty string. The long option can also be written
`--davix-opts-file`.

This option is cumulative (together with the previous one), every occurence of
the option will append the value read from the file to the set of options that
will be passed to `davix` with a whitespace separator. The following
pseudo-example reads the beginning of authentication options from the command
line and the password from a file:

```shell
./davix-backup.sh -o "--userlogin myuser --userpass" -O my-secret-file --
```

### `-d` or `--destination`

Takes the (remote) location directory where to place files as an argument. It
defaults to the local directory. `davix-backup` will attempt to create the
directory, including the entire path of directories when these do not exist. In
order to be able to specify remote locations starting with `http://` or
`https://`, you will need proper support for `davix`, see options `--davix` and
`--davix-options`. The long option can be shortened to anything that starts with
`--dest`.

### `-k` or `--keep`

Number of copies of the files to be kept at the destination location. The
default value is empty, meaning that all copies will be kept.

### `-c` or `--compression`

Takes the compression level as an argument and defaults to `-1`, meaning no
compression at all: the selected files will be copied as is to the destination.
As soon as compression is greater or equal to `0`, `davix-backup` will attempt
to compress to an archive in a temporary directory. `zip`, when present is
preferred because it is able to perform some encryption on the archive using a
password. When not present, `gzip` will be used instead, if available. See
option `--compressor`.

### `-w` or `--password`

Takes the password to use for `zip` archive encryption. Default to an empty
string, meaning no encryption. The long option can be abbreviated to `--pass`.

### `-W` or `--password-file`

Same as the `--password` option, but takes the path to a file from which the
password will be read. This is useful for integration with Docker secrets for
example.

### `-z` or `--compressor` or `--zipper`

Takes the path to the compressing binary to use for compression. Only `zip` and
`gzip` are recognised. Password encryption is only supported by `zip`.

### `-t` or `--then`

Takes a command to execute once the backup operation has ended. The default is
an empty string, meaning that no command will be executed. When a command is
specified, it will take the path to the destination resource that was created.

### `--wait`

Wait for a number of seconds before the (first) copy operation. The default is
not to wait at all. Whenever the value of the period contains a `:` sign, a
random value between both periods on each side of the `:` sign will be computed.
Periods can be integers, but also human readable strings such as `5M` or `5
Minutes`, etc.

### `-r` or `--repeat`

Repeat the copy operation, waiting for this many seconds between the start of
the copy and the next attempt. The period is in seconds, and can also be
expressed in human-readable forms (see `--wait`). The default is not to wait and
perform a single copy operation.