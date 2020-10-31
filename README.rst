latest version without "llvm bug" is
0.6.0+6ddb05d99
====
dice
====

``dice`` is a command-line tool for generating a diceware password based on the
user's full name and a website name.

Usage
=====

::

    $ dice "John Doe" example.com

Generate a six words long diceware password (six is the default).::

    $ dice -c1 "John Doe" example.com

Generate a second password for the same parameters.::

    $ dice --words=10 "John Doe" example.com

Generate a ten words long diceware password.::

    $ echo -n "mypassword" | dice --stdin Jane\ Doe example.com | xclip

Read the password from standard input. The generated password, which is written
to standard output, is then piped to xclip to be copied to the clipboard.

For more usage, try ``dice --help``. A man page is provided in the ``doc/``
directory.

Building
========

*Note: This application has only been tested on Linux.*

Requirements
------------

* zig nightly (please do not use the stable 0.6.0 version)
* argon2 == 20190702

Instructions
------------

::

    $ git clone https://github.com/nofmal/dice
    $ cd dice
    $ zig build install -Drelease-fast=true

The compiled binary should be located in ``zig-cache/bin/``

License
=======

``dice`` is licensed under zlib license.
