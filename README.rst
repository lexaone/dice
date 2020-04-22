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

    $ echo -n "example password" | dice --stdin Jane\\ Doe example.com | xclip
    -selection clipboard

Read the password from standard input. The generated password, which is written
to standard output, is then piped to xclip to be copied to the clipboard.

For more usage, try ``dice --help``. The ``doc/`` directory contains a manpage.

Building
========

*Note: This application has only been tested on Linux and compiled successfully
against zig 0.6.0*

Dependencies
------------

* zig == 0.6.0
* argon2 == 20190702

Instructions
------------

::

    $ git clone https://github.com/nofmal/dice
    $ cd dice
    $ zig build install -Drelease-fast=true

The compiled binary should be located in ``./zig-cache/bin/``

License
=======

``dice`` is licensed under zlib license.
